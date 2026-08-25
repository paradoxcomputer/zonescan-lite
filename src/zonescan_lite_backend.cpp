#include "zonescan_lite_backend.h"


#include <QCoreApplication>
#include <QDateTime>
#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QNetworkAccessManager>
#include <QSettings>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUrl>

#include <cstdlib>
#include <string>

Q_LOGGING_CATEGORY(lcZonescan, "zonescan.lite")

// ── HTTP ─────────────────────────────────────────────────────────────────────
// Merged in from the former zonescan_bridge module. That module existed to make
// zonescan's API callable from other Logos modules, but nothing else ever consumed it, and
// splitting it out did NOT keep blocking IO off the UI thread: this backend called it inline
// and blocked for the whole round trip either way. Keeping it separate therefore bought an
// extra install, an extra package to sign and publish, and one IPC hop per call, for no gain.
namespace {

constexpr const char* kDefaultNode = "https://zonescan.paradox.computer";

// Named for the env var rather than the property: the generated source exposes a baseUrl()
// getter for the `baseUrl` PROP, and a bare baseUrl() inside a member function resolves to
// that one. Empty when unset, so the caller can tell "not set" from "set to the default".
QString envNode() {
    const char* env = std::getenv("ZONESCAN_BASE_URL");
    return (env && *env) ? QString::fromUtf8(env) : QString();
}

// Where the chosen node is remembered. Explicit org/app so it lands somewhere predictable
// (~/.config/paradox.computer/zonescan_lite.conf) regardless of what the host names itself.
QSettings nodeSettings() { return QSettings(QStringLiteral("paradox.computer"), QStringLiteral("zonescan_lite")); }

// Trim, tolerate a missing scheme, drop trailing slashes, and require an http(s) host.
// Returns an empty string when the input cannot be a usable origin.
QString normalizeNode(const QString& raw) {
    QString v = raw.trimmed();
    if (v.isEmpty()) return QString();
    if (!v.contains(QStringLiteral("://"))) v.prepend(QStringLiteral("https://"));
    while (v.endsWith(QLatin1Char('/'))) v.chop(1);
    const QUrl u(v);
    const QString scheme = u.scheme().toLower();
    if (!u.isValid() || u.host().isEmpty()
        || (scheme != QStringLiteral("http") && scheme != QStringLiteral("https")))
        return QString();
    return v;
}

// One QNAM for the module's lifetime, created lazily on the module thread (the logos_host Qt
// thread that dispatches our calls), which owns the event loop the blocking calls below spin.
QNetworkAccessManager& nam() {
    static QNetworkAccessManager manager;
    return manager;
}

// Failures travel as JSON so they survive the QString-shaped HTTP helpers unchanged.
// `status` is the HTTP code when the server answered at all and 0 when it never did: the
// view needs that split to tell "this hash does not exist" (404) from "the request did not
// land" (0/5xx), which used to render identically as "not found".
QString errorJson(const QString& msg, int status = 0) {
    QString escaped = msg;
    escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"))
           .replace(QLatin1Char('"'), QStringLiteral("\\\""));
    return QStringLiteral("{\"error\":\"") + escaped + QStringLiteral("\",\"status\":")
         + QString::number(status) + QStringLiteral("}");
}

// Percent-encode a path segment (hashes/ids are hex/base58 - safe - but be strict).
QString encodeSegment(const QString& s) {
    return QString::fromUtf8(s.toUtf8().toPercentEncoding());
}

QString withQuery(const QString& path, const QString& query) {
    return query.isEmpty() ? path : path + QLatin1Char('?') + query;
}

constexpr int kTimeoutMs = 15000;

// Run a prepared reply to completion on a nested event loop, bounded by a timeout.
// `preferBody` returns a 4xx JSON body in place of the transport error, which is what the
// submit/decode endpoints use to explain a rejection.
QString finishReply(QNetworkReply* reply, bool preferBody) {
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    timer.start(kTimeoutMs);
    loop.exec();

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    QString out;
    if (!timer.isActive()) {
        reply->abort();
        out = errorJson(QStringLiteral("request timed out after 15s"), 0);
    } else if (reply->error() != QNetworkReply::NoError) {
        const QString body = QString::fromUtf8(reply->readAll());
        out = (preferBody && !body.isEmpty()) ? body : errorJson(reply->errorString(), status);
    } else {
        out = QString::fromUtf8(reply->readAll());
        if (out.isEmpty()) out = errorJson(QStringLiteral("empty response"), status);
    }
    reply->deleteLater();
    return out;
}

} // namespace

QString ZonescanLiteBackend::httpGet(const QString& path) {
    return httpGetFrom(m_baseUrl, path);
}

QString ZonescanLiteBackend::httpGetFrom(const QString& base, const QString& path) {
    const QUrl url(base + path);
    if (!url.isValid()) return errorJson(QStringLiteral("bad url"));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("zonescan_lite/") + QStringLiteral(ZONESCAN_LITE_VERSION));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    return finishReply(nam().get(req), false);
}

QString ZonescanLiteBackend::httpPostTo(const QUrl& url, const QString& body) {
    if (!url.isValid()) return errorJson(QStringLiteral("bad url"));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("zonescan_lite/") + QStringLiteral(ZONESCAN_LITE_VERSION));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    return finishReply(nam().post(req, body.toUtf8()), true);
}

QString ZonescanLiteBackend::httpPost(const QString& path, const QString& body) {
    return httpPostTo(QUrl(m_baseUrl + path), body);
}

namespace {

constexpr int kPollIntervalMs = 2000;

// The HTTP helpers return compact JSON strings. An empty string (or one shaped
// {"error":…}) means "not ready / failed", not "empty result".
bool isError(const QString& json) {
    if (json.isEmpty()) return true;
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    return doc.isObject() && doc.object().contains(QStringLiteral("error"));
}

QString errorTextOf(const QString& json) {
    if (json.isEmpty()) return QStringLiteral("no response");
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (doc.isObject()) {
        const QJsonObject o = doc.object();
        if (o.contains(QStringLiteral("error"))) return o.value(QStringLiteral("error")).toString();
    }
    return QStringLiteral("malformed response");
}

QVariantMap jsonToMap(const QString& json) {
    if (json.isEmpty()) return {};
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    return doc.isObject() ? doc.object().toVariantMap() : QVariantMap();
}

QVariantList jsonToList(const QString& json) {
    if (json.isEmpty()) return {};
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    return doc.isArray() ? doc.array().toVariantList() : QVariantList();
}

// Wrap an object-returning endpoint as { ok, … } / { ok:false, error, status }.
QVariantMap mapResult(const QString& json) {
    QVariantMap out;
    if (json.isEmpty()) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("no response");
        out[QStringLiteral("status")] = 0;
        return out;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("malformed response");
        out[QStringLiteral("status")] = 0;
        return out;
    }
    out = doc.object().toVariantMap();
    const bool failed = out.contains(QStringLiteral("error"));
    // Some endpoints (notably /api/schemas/submit) publish their OWN `ok` to mean "the server
    // accepted this". Don't clobber it: `ok` here means the call reached the server AND the
    // server was happy, which is exactly what every caller branches on.
    const bool serverSaysNo = out.contains(QStringLiteral("ok"))
                              && !out.value(QStringLiteral("ok")).toBool();
    out[QStringLiteral("ok")] = !failed && !serverSaysNo;
    if (failed && !out.contains(QStringLiteral("status"))) out[QStringLiteral("status")] = 0;
    return out;
}

// Wrap an array-returning endpoint as { ok, items } / { ok:false, error, status }.
// The array MUST NOT collapse into a bare [] on failure: every feed treats a short page as
// the end of the list, so a single timed-out request used to latch the feed "done" and
// render an outage as an empty chain.
QVariantMap listResult(const QString& json, const QString& key) {
    QVariantMap out;
    if (isError(json)) {
        const QVariantMap e = jsonToMap(json);
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = e.value(QStringLiteral("error"), errorTextOf(json));
        out[QStringLiteral("status")] = e.value(QStringLiteral("status"), 0);
        return out;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isArray()) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("malformed response");
        out[QStringLiteral("status")] = 0;
        return out;
    }
    out[QStringLiteral("ok")] = true;
    out[key] = doc.array().toVariantList();
    return out;
}

} // namespace

ZonescanLiteBackend::ZonescanLiteBackend() {
    setConnectionStatus(QStringLiteral("Connecting"));
    setLastOkUnix(0);
    setVersion(QStringLiteral(ZONESCAN_LITE_VERSION));

    // saved setting > $ZONESCAN_BASE_URL > built-in default. The saved value wins so the
    // settings panel is always the thing in charge of what it shows; the env var supplies the
    // starting point when nothing has been chosen, which is what a dev pointing at a local
    // zonescan wants. `nodeSource` tells the panel which of the three is in force.
    const QString saved = normalizeNode(nodeSettings().value(QStringLiteral("nodeUrl")).toString());
    const QString env = normalizeNode(envNode());
    if (!saved.isEmpty())      { m_baseUrl = saved; setNodeSource(QStringLiteral("saved")); }
    else if (!env.isEmpty())   { m_baseUrl = env;   setNodeSource(QStringLiteral("env")); }
    else                       { m_baseUrl = QString::fromUtf8(kDefaultNode); setNodeSource(QStringLiteral("default")); }
    setBaseUrl(m_baseUrl);
}

ZonescanLiteBackend::~ZonescanLiteBackend() {
    m_shuttingDown = true;
    if (m_pollTimer) m_pollTimer->stop();
}

void ZonescanLiteBackend::reportError(const QString& what, const QString& detail) {
    const QString msg = detail.isEmpty() ? what : (what + QStringLiteral(": ") + detail);
    qCWarning(lcZonescan).noquote() << msg;
    // While an outage lasts the poll fails every 2 s; say it once, not thirty times a minute.
    // But DECAY rather than latch: the first poll runs inside onContextReady(), which the
    // generated glue calls before setBackend(), so that emission reaches no replica. A pure
    // latch would then silence an entire cold-start outage. Repeat every ~30 s instead.
    if (msg == m_lastErrorSent && (++m_errorRepeats % 15) != 0) return;
    if (msg != m_lastErrorSent) m_errorRepeats = 0;
    m_lastErrorSent = msg;
    Q_EMIT error(msg);
}

void ZonescanLiteBackend::onContextReady() {
    // Single-shot and re-armed at the END of poll(): a repeating timer would keep firing
    // into the nested event loop that every blocking request spins, so a 15 s stall used to
    // stack roughly seven nested polls, each able to publish state out of order.
    m_pollTimer = new QTimer(this);
    m_pollTimer->setSingleShot(true);
    m_pollTimer->setInterval(kPollIntervalMs);
    connect(m_pollTimer, &QTimer::timeout, this, &ZonescanLiteBackend::poll);
    // Stop polling the instant we begin quitting: a synchronous cross-process
    // call landing mid-teardown blocks on a dead peer and freezes the window.
    connect(qApp, &QCoreApplication::aboutToQuit, this,
            [this]() { m_shuttingDown = true; if (m_pollTimer) m_pollTimer->stop(); });
    poll();   // fill immediately, don't wait a full interval
}

void ZonescanLiteBackend::poll() {
    if (m_busy || m_shuttingDown) return;   // re-entered from a nested loop, or tearing down
    m_busy = true;
    // Re-arm on every exit path, so one failed cycle can never end the polling.
    struct Rearm {
        ZonescanLiteBackend* self;
        ~Rearm() {
            self->m_busy = false;
            // aboutToQuit can be delivered by the nested event loop a blocking request spins,
            // i.e. while this poll is mid-flight. Re-arming then would undo the stop() and keep
            // firing synchronous calls into a peer that is going away.
            if (self->m_pollTimer && !self->m_shuttingDown)
                self->m_pollTimer->start(kPollIntervalMs);
        }
    } rearm{this};

    const QString stateJson = httpGet(QStringLiteral("/api/state"));
    if (isError(stateJson)) {
        setConnectionStatus(m_connectedOnce ? QStringLiteral("Error")
                                            : QStringLiteral("Connecting"));
        reportError(QStringLiteral("could not reach zonescan"), errorTextOf(stateJson));
        return;
    }
    m_connectedOnce = true;
    m_lastErrorSent.clear();   // recovered — the next failure is news again
    setConnectionStatus(QStringLiteral("Connected"));
    setState(jsonToMap(stateJson));
    setLastOkUnix(QDateTime::currentSecsSinceEpoch());

    const QString txsJson = httpGet(QStringLiteral("/api/txs"));
    if (!isError(txsJson)) setTxs(jsonToList(txsJson));

    // Program registry (names/guesses/schemas) changes server-side on an interval —
    // fetch on first fill, then every ~30 s (15 polls). Guesses refresh a bit more.
    const bool first = programs().isEmpty() && guesses().isEmpty();
    if (first || (m_registryTick % 15) == 0) {
        const QString pJson = httpGet(QStringLiteral("/api/programs"));
        if (!isError(pJson)) setPrograms(jsonToMap(pJson));
        const QString sJson = httpGet(QStringLiteral("/api/schemas"));
        if (!isError(sJson)) setSchemas(jsonToMap(sJson));
    }
    if (first || (m_registryTick % 6) == 0) {
        const QString gJson = httpGet(QStringLiteral("/api/program_guesses"));
        if (!isError(gJson)) setGuesses(jsonToMap(gJson));
    }
    ++m_registryTick;
}

// A manual refresh from the view. If a poll is already running the cycle is in hand and
// re-entering it would only nest another request inside the blocked one.
void ZonescanLiteBackend::refresh() {
    if (m_busy || m_shuttingDown) return;
    if (m_pollTimer) m_pollTimer->stop();
    poll();
}

QVariantMap ZonescanLiteBackend::getTx(QString hash) {
    return mapResult(httpGet(QStringLiteral("/api/tx/") + encodeSegment(hash)));
}

// Zone-scoped variant. Prefer this wherever the caller knows which zone it is showing: a
// transaction hash is not unique across zones, so an unscoped lookup can return another
// zone's copy of an identical (e.g. genesis) transaction.
QVariantMap ZonescanLiteBackend::getTxOn(QString hash, QString channel) {
    const QString query = channel.isEmpty() ? QString() : QStringLiteral("channel=") + channel;
    return mapResult(httpGet(withQuery(QStringLiteral("/api/tx/") + encodeSegment(hash), query)));
}

// Decode blocks read from a sequencer on the user's own machine. The server has never seen
// that chain; it only decodes what it is handed and stores nothing.
//
// The outcome is explicit: ok=false means zonescan's decoder could not be reached, which is
// NOT the same as ok=true with an empty `blocks` (the batch held no LEZ blocks). Collapsing
// the two made a zonescan outage read as "your chain contains nothing we recognise".
QVariantMap ZonescanLiteBackend::decodeBlocks(QString body) {
    const QString json = httpPost(QStringLiteral("/api/decode"), body);
    QVariantMap out = mapResult(json);
    if (out.value(QStringLiteral("ok")).toBool() && !out.contains(QStringLiteral("blocks")))
        out[QStringLiteral("blocks")] = QVariantList();
    return out;
}

// One JSON-RPC call against the sequencer the user named. The result is unwrapped to
// {result} / {error} so the view never has to know the JSON-RPC envelope.
QVariantMap ZonescanLiteBackend::localRpc(QString url, QString method, QVariantList params) {
    QJsonObject req;
    req[QStringLiteral("jsonrpc")] = QStringLiteral("2.0");
    req[QStringLiteral("id")] = 1;
    req[QStringLiteral("method")] = method;
    req[QStringLiteral("params")] = QJsonArray::fromVariantList(params);
    const QString body = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));
    // The target is user-supplied, so it must never inherit the zonescan base URL, and only
    // an explicit http/https host is accepted. Unlike a browser there is no same-origin policy
    // to satisfy, so plain HTTP to loopback is all this needs.
    const QUrl target(url);
    const QString scheme = target.scheme().toLower();
    if (!target.isValid() || target.host().isEmpty()
        || (scheme != QStringLiteral("http") && scheme != QStringLiteral("https"))) {
        QVariantMap bad;
        bad[QStringLiteral("ok")] = false;
        bad[QStringLiteral("error")] = QStringLiteral("bad sequencer url");
        bad[QStringLiteral("status")] = 0;
        return bad;
    }
    const QVariantMap m = jsonToMap(httpPostTo(target, body));
    QVariantMap out;
    const bool failed = m.contains(QStringLiteral("error")) || !m.contains(QStringLiteral("result"));
    out[QStringLiteral("ok")] = !failed;
    if (m.contains(QStringLiteral("error")))  out[QStringLiteral("error")]  = m.value(QStringLiteral("error"));
    if (m.contains(QStringLiteral("status"))) out[QStringLiteral("status")] = m.value(QStringLiteral("status"));
    if (m.contains(QStringLiteral("result"))) out[QStringLiteral("result")] = m.value(QStringLiteral("result"));
    if (failed && !out.contains(QStringLiteral("error")))
        out[QStringLiteral("error")] = QStringLiteral("sequencer returned no result");
    return out;
}

QVariantMap ZonescanLiteBackend::getTxsQuery(QString query) {
    return listResult(httpGet(withQuery(QStringLiteral("/api/txs"), query)),
                      QStringLiteral("items"));
}
QVariantMap ZonescanLiteBackend::getAccountQuery(QString id, QString query) {
    return mapResult(httpGet(withQuery(QStringLiteral("/api/account/") + encodeSegment(id), query)));
}
QVariantMap ZonescanLiteBackend::getTokenQuery(QString id, QString query) {
    return mapResult(httpGet(withQuery(QStringLiteral("/api/token/") + encodeSegment(id), query)));
}
QVariantMap ZonescanLiteBackend::getTokenHolders(QString id, QString query) {
    return mapResult(httpGet(withQuery(QStringLiteral("/api/token/") + encodeSegment(id) + QStringLiteral("/holders"), query)));
}
QVariantMap ZonescanLiteBackend::getProgramQuery(QString id, QString query) {
    return mapResult(httpGet(withQuery(QStringLiteral("/api/program/") + encodeSegment(id), query)));
}
QVariantMap ZonescanLiteBackend::getTokenOf(QString account, QString channel) {
    // `channel` is NOT optional server-side: zonescan's TokenOfQuery declares it a plain
    // String, so omitting it answers 400 "missing field `channel`" rather than resolving
    // zone-agnostically. Send it unconditionally, empty when unknown, which is what the web
    // dashboard does. Dropping it here made token transfers fall back to the raw account.
    QString q = QStringLiteral("account=") + QString::fromUtf8(QUrl::toPercentEncoding(account))
              + QStringLiteral("&channel=") + QString::fromUtf8(QUrl::toPercentEncoding(channel));
    return mapResult(httpGet(withQuery(QStringLiteral("/api/token_of"), q)));
}
QVariantMap ZonescanLiteBackend::getSchemas() {
    QVariantMap out = mapResult(httpGet(QStringLiteral("/api/schemas")));
    // A manual refresh republishes the PROP too, so every open page re-decodes at once.
    if (out.value(QStringLiteral("ok")).toBool()) {
        QVariantMap payload = out;
        payload.remove(QStringLiteral("ok"));
        setSchemas(payload);
    }
    return out;
}
QVariantMap ZonescanLiteBackend::submitSchema(QString body) {
    return mapResult(httpPost(QStringLiteral("/api/schemas/submit"), body));
}
QVariantMap ZonescanLiteBackend::whatIs(QString value) {
    return mapResult(httpGet(QStringLiteral("/api/whatis/") + encodeSegment(value)));
}
QVariantMap ZonescanLiteBackend::getElf(QString hash) {
    return mapResult(httpGet(QStringLiteral("/api/elf/") + encodeSegment(hash)));
}

// ── node selection ───────────────────────────────────────────────────────────

// Is `base` a reachable zonescan node? "Reachable" alone is not enough — a parked domain, a
// proxy or the wrong service will happily answer 200. A zonescan node is identified by
// /api/state returning a JSON OBJECT carrying a `sequencers` array and an `l1` object, which
// is the shape every page in this view reads.
QVariantMap ZonescanLiteBackend::probeNode(const QString& base) {
    QVariantMap out;
    out[QStringLiteral("ok")] = false;
    if (base.isEmpty()) {
        out[QStringLiteral("error")] = QStringLiteral("Enter an http(s) address, e.g. https://zonescan.paradox.computer");
        return out;
    }
    // Hold the poll guard for the duration: the poller shares this thread, this event loop and
    // this connection pool, so a probe issued while a poll is mid-flight competes with it. This
    // stops a poll STARTING inside the probe; it cannot un-start one already running.
    const bool wasBusy = m_busy;
    m_busy = true;
    QString json;
    // Two attempts, and only for a timeout. One slow round trip must not reject a node that is
    // perfectly fine — which is exactly what a user hit re-entering the default while the
    // server was having a slow minute.
    for (int attempt = 0; attempt < 2; ++attempt) {
        json = httpGetFrom(base, QStringLiteral("/api/state"));
        if (!isError(json)) break;
        if (!errorTextOf(json).contains(QStringLiteral("timed out"))) break;
    }
    m_busy = wasBusy;

    if (isError(json)) {
        const QString why = errorTextOf(json);
        out[QStringLiteral("error")] = why.contains(QStringLiteral("timed out"))
            ? (base + QStringLiteral(" did not answer in time (tried twice). It may be slow or "
                                     "unreachable from here — check the address, or try again."))
            : (QStringLiteral("Could not reach ") + base + QStringLiteral(" — ") + why);
        return out;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) {
        out[QStringLiteral("error")] = base + QStringLiteral(" answered, but not with JSON. Is it a zonescan node?");
        return out;
    }
    const QJsonObject o = doc.object();
    if (!o.value(QStringLiteral("sequencers")).isArray() || !o.value(QStringLiteral("l1")).isObject()) {
        out[QStringLiteral("error")] = base + QStringLiteral(" answered, but it does not look like a zonescan node "
                                                            "(no sequencers/l1 in /api/state).");
        return out;
    }
    out[QStringLiteral("ok")] = true;
    out[QStringLiteral("url")] = base;
    out[QStringLiteral("node")] = o.value(QStringLiteral("node")).toString();
    out[QStringLiteral("zones")] = o.value(QStringLiteral("sequencers")).toArray().size();
    out[QStringLiteral("txTotal")] = o.value(QStringLiteral("tx_total")).toVariant();
    return out;
}

// Repoint at `url`. Everything already published describes the OLD node, so it is dropped
// rather than left on screen under the new node's name until the first poll lands.
void ZonescanLiteBackend::applyNode(const QString& url, const QString& source) {
    qCWarning(lcZonescan).noquote() << "switching node to" << url << "(" << source << ")";
    m_baseUrl = url;
    setBaseUrl(url);
    setNodeSource(source);

    setState(QVariantMap());
    setTxs(QVariantList());
    setPrograms(QVariantMap());
    setGuesses(QVariantMap());
    setSchemas(QVariantMap());
    setLastOkUnix(0);

    m_connectedOnce = false;
    m_registryTick = 0;
    m_lastErrorSent.clear();
    m_errorRepeats = 0;
    setConnectionStatus(QStringLiteral("Connecting"));

    // Guarded, so a switch made from inside a blocked poll's nested event loop does not stack
    // another one; the re-armed timer picks it up within the interval either way.
    poll();
}

QVariantMap ZonescanLiteBackend::checkNode(QString url) {
    return probeNode(normalizeNode(url));
}

QVariantMap ZonescanLiteBackend::setNodeUrl(QString url) {
    // Empty means "forget my choice": clear the saved value and fall back to the env var or
    // the built-in default. Deliberately NOT probed — reset has to work while offline, or a
    // bad saved node would be unrecoverable from the UI.
    if (url.trimmed().isEmpty()) {
        QSettings s = nodeSettings();
        s.remove(QStringLiteral("nodeUrl"));
        s.sync();
        const QString env = normalizeNode(envNode());
        const QString next = env.isEmpty() ? QString::fromUtf8(kDefaultNode) : env;
        applyNode(next, env.isEmpty() ? QStringLiteral("default") : QStringLiteral("env"));
        QVariantMap out;
        out[QStringLiteral("ok")] = true;
        out[QStringLiteral("url")] = next;
        out[QStringLiteral("reset")] = true;
        return out;
    }

    const QString norm = normalizeNode(url);
    QVariantMap probe = probeNode(norm);
    if (!probe.value(QStringLiteral("ok")).toBool()) return probe;   // rejected: nothing changed

    QSettings s = nodeSettings();
    s.setValue(QStringLiteral("nodeUrl"), norm);
    s.sync();
    applyNode(norm, QStringLiteral("saved"));
    return probe;
}
