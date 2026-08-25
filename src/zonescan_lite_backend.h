#pragma once

#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include "logos_ui_plugin_context.h"
#include "rep_zonescan_lite_source.h"

class QTimer;

// Single-sourced from metadata.json by CMake (see CMakeLists.txt). The fallback only
// applies to an out-of-tree build that bypasses it; CI asserts the two agree.
#ifndef ZONESCAN_LITE_VERSION
#define ZONESCAN_LITE_VERSION "0.0.0-dev"
#endif

/**
 * @brief Backend for the ZoneScan ui_qml view (universal model).
 *
 * The only hand-written C++ in this module: it derives the repc-generated
 * `ZonescanLiteSimpleSource` (implements the `.rep` view contract) and
 * `LogosUiPluginContext` (supplies `onContextReady()`). The `*Plugin` / `*Interface`
 * glue is generated.
 *
 * It calls zonescan's REST API directly (the former zonescan_bridge module, merged in:
 * nothing else consumed it, and splitting it out did not move blocking IO off any thread),
 * parses the JSON into QVariant for QML, and polls every 2 s to keep `state` / `txs` live.
 */
class ZonescanLiteBackend : public ZonescanLiteSimpleSource, public LogosUiPluginContext {
public:
    ZonescanLiteBackend();
    ~ZonescanLiteBackend() override;

    // Blocking HTTP against zonescan, merged in from the former zonescan_bridge module.
    // Blocking is safe here for the same reason it was there: these run on the module thread
    // that dispatches our calls, not the QML render thread, and QML awaits the result through
    // logos.watch() at the QtRO boundary.
    //
    // It is NOT safe against re-entrancy, though: each call spins a nested QEventLoop, which
    // keeps delivering timer events, so the repeating poll timer fires *inside* a request that
    // is still blocked. Everything that can start a request therefore goes through the
    // m_busy guard below.
    QString httpGet(const QString& path);
    QString httpPost(const QString& path, const QString& body);
    QString httpPostTo(const QUrl& url, const QString& body);
    // Same GET, but against an explicit origin — used to probe a candidate node before it is
    // allowed to become m_baseUrl.
    QString httpGetFrom(const QString& base, const QString& path);

    // Fired when the host wires LogosAPI: modules() is live — start the poll here.
    void onContextReady() override;

    // .rep SLOTs
    void refresh() override;
    QVariantMap getTx(QString hash) override;
    QVariantMap getTxOn(QString hash, QString channel) override;
    QVariantMap decodeBlocks(QString body) override;
    QVariantMap localRpc(QString url, QString method, QVariantList params) override;
    QVariantMap getTxsQuery(QString query) override;
    QVariantMap getAccountQuery(QString id, QString query) override;
    QVariantMap getTokenQuery(QString id, QString query) override;
    QVariantMap getTokenHolders(QString id, QString query) override;
    QVariantMap getProgramQuery(QString id, QString query) override;
    QVariantMap getTokenOf(QString account, QString channel) override;
    QVariantMap getSchemas() override;
    QVariantMap submitSchema(QString body) override;
    QVariantMap whatIs(QString value) override;
    QVariantMap getElf(QString hash) override;
    QVariantMap checkNode(QString url) override;
    QVariantMap setNodeUrl(QString url) override;

private:
    void poll();   // pull state + txs, publish PROPs, set connectionStatus

    // Every entry point that issues a blocking request takes this. A nested event loop
    // re-delivers the poll timer (and can re-deliver a QtRO call), so without it an outage
    // stacks one nested poll per timer tick for the whole 15 s timeout, and an older
    // nested poll's setState() can publish after a newer one's.
    bool m_busy = false;
    // Set on aboutToQuit. QCoreApplication::closingDown() is false for the whole quit
    // sequence (it flips inside ~QCoreApplication), so it cannot be used to keep the poll
    // timer stopped once teardown has begun.
    bool m_shuttingDown = false;

    // Report a failed request once: qCWarning for the maintainer, error() for the view.
    void reportError(const QString& what, const QString& detail);

    // The origin every request goes to. Resolved at construction from
    //   saved QSettings value  >  $ZONESCAN_BASE_URL  >  the built-in default
    // and changed at runtime by setNodeUrl(). Held as state rather than re-read per call so a
    // switch takes effect atomically for every subsequent request.
    QString m_baseUrl;
    // Probe a candidate origin: reachable AND shaped like a zonescan node.
    QVariantMap probeNode(const QString& base);
    // Repoint at `url`: publish it, drop every cached snapshot, and re-poll from scratch.
    void applyNode(const QString& url, const QString& source);

    QTimer* m_pollTimer = nullptr;
    bool m_connectedOnce = false;
    int m_registryTick = 0;   // refetch programs/schemas periodically (they change server-side)
    QString m_lastErrorSent;  // don't re-emit the same message every 2 s while an outage lasts
    int m_errorRepeats = 0;   // ...but do repeat it occasionally; see reportError()
};
