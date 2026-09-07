# Workflow des Plugins

Der Ablauf ist im CoffeeScript geregelt.

## Schritt 1 — Dateikopf und Klassendeklaration

```
PLUGIN_ID = 'fylr-plugin-ubhd-3d-viewer'
PLUGIN_SCRIPT_SRC = if typeof document isnt 'undefined' then document.currentScript?.src else null
```

`PLUGIN_SCRIPT_SRC` speichert beim Laden die URL der Skript-Datei. `document` bezeichnet als globale Variable das aktuelle DOM. Falls `currentScript` nicht null ist, gib `.src` zurück, sonst null. Im serverseitigen Node.js existiert `document` nicht, deswegen die Prüfung auf `undefined`.

```
class UBHD3DViewerPlugin extends AssetDetail
```

Das Plugin erbt von `AssetDetail`. Fylr ruft das Plugin auf, falls ein Asset angezeigt wird.

```
constructor: (args...) ->
    super(args...)
    @viewerModulePromise = null
```

Alle Parameter aus `UBHDViewerPlugin` werden an `AssetDetail` weitergereicht. `@viewerModulePromise` (wie `this.viewerModulePromise`) bezeichnet einen Cache-Platzhalter, damit das Plugin nur einmal geladen wird. Das Plugin setzt diesen Parameter beim ersten Aufruf von importViewerModule() (s. Schritt 4).

## Schritt 2 — Hilfsfunktionen für DOM-Elemente

```
normalizeElement: (target) ->
    return null unless target?
    return target[0] if target.jquery?
    return target.get(0) if typeof target.get is 'function'
    target
```

Dem Plugin kann ein jQuery-Objekt oder ein natives DOM-Element übergeben werden. Ein jQuery-Objekt ist ein Wrapper um echte DOM-Elemente und vereinfacht deren Manipulation, Event Handling und CSS-Styling (s. https://jquery.com/). CUI (CoffeeScript User Interface, s. https://github.com/programmfabrik/coffeescript-ui) ist das UI-Framework, das fylr intern für alle seine Komponenten nutzt – es hat allerdings kein `.get()`-Method; CUI-Objekte liefern das DOM-Element über eine `.DOM`-Property.

`normalizeElement` erzeugt daraus immer ein echtes DOM-Element:
1. jQuery-Objekte haben `.jquery` als Property → `target[0]`
2. Jedes Objekt mit einer `.get()`-Funktion → `target.get(0)` (generisches Duck-Typing als Fallback für andere jQuery-ähnliche Wrapper)
3. Alles andere kommt unverändert zurück

## Schritt 3 — Plugin-URL ermitteln

Damit das Plugin die URL zum Viewer (in `lib/ubhd-3d-viewer`) basteln kann, muss es wissen wo genau es im Server liegt. Dafür gibt es drei Methoden:

`getPluginScript()` ermittelt das `<script>` Tag im DOM. Falls `currentScript` fehlschlägt, werden alle Skripte im DOM per RegEx durchsucht.

`normalizePluginBaseUrl(value)` baut mithilfe der `URL` Klasse eine saubere URL mit abschließendem Slash. Beispielsweise wird `https://example.com/abc/viewer/ubhd3d.js` zu `https://example.com/abc/viewer/`.

`getPluginBaseUrl` probiert als Quelle:
1. den fylr Plugin Manager: `ez5.pluginManager`,
2. die beim Laden gespeicherte URL: `PLUGIN_SCRIPT_SRC`
3. als Fallback `getPluginScript()`

```
getViewerUrls: ->
    pluginBaseUrl = @getPluginBaseUrl()
    return null unless pluginBaseUrl?
    pageUrl: new URL('viewer-dist/', pluginBaseUrl).href
    rtiPageUrl: new URL('rti-dist/index.html', pluginBaseUrl).href
```

Diese Methode gibt ein Objekt mit zwei URLs zurück: die eine für den THREE.js basierten Viewer, die andere für RTI-Dateien (hier gibt es eine eigene Library: OpenLIME)

## Schritt 4 — Stylesheet und Modul laden

```
ensureViewerStylesheet: (cssUrl) ->
    return unless cssUrl?

    existingLink = document.querySelector("link[data-ubhd-viewer-css='#{cssUrl}']")
    return if existingLink?
    link = document.createElement('link')
    ...
    document.head.appendChild(link)
```

Füge CSS des Viewers in den `<head>` ein. Falls `<link>` bereits existiert, passiert nichts.

```
importViewerModule: (moduleUrl) ->
    unless @viewerModulePromise?
        @viewerModulePromise = Function('url', 'return import(url)')(moduleUrl)
    @viewerModulePromise
```

Der Viewer wird dynamisch (asynchron) mit `import()` nachgeladen. CoffeeScript-Compiler können `import()` in eigene Syntax umwandeln oder als Syntaxfehler behandeln. Der `Function()`-Trick umgeht den Compiler vollständig, indem der `import()`-Aufruf erst zur Laufzeit als String erzeugt wird – der Compiler sieht kein statisches `import` und erzeugt keinen Build-Fehler.

## Schritt 5 — URL-Prüfung und Asset-Auswahl

`__probeUrlStatus` ermittelt den HTTP-Status einer URL, bevorzugt über einen (datensparenden) `HEAD`-Request (d.h. ohne Body). Es gibt zwei verschiedene Fehlerpfade: Falls der Server `HEAD` aktiv verbietet (Status 405 oder 501), wird innerhalb von `.then()` auf `GET` mit `Range: bytes=0-0` umgestellt. Falls der Request komplett scheitert (z.B. durch einen Netzwerkfehler oder CORS-Blockierung), greift `.catch()` und startet ebenfalls einen `GET`-Fallback. Falls `fetch` nicht verfügbar ist, wird `$.ajax` benutzt.

`__pickFirstAccessible(assetInfos)` prüft mithilfe von `__probeUrlStatus` nacheinander mehrere Asset-Kandidaten auf ihren HTTP-Status und wählt den ersten, der erreichbar ist (Statuscode 2xx). Eine Schleife wie in `for candidate in candidates` ist nicht möglich, da die Prüfung asynchron laufen soll; stattdessen wird `checkNext()` rekursiv (d.h. am Ende des Promise) aufgerufen. 

```
__bestVersionUrl: (version) ->
    return null unless version?
    return version.url if version.url?
    return version.versions?.original?.url if version.versions?.original?.url?
    null
```

## Schritt 6 — Dateityp-Erkennung und Priorisierung

```
modelTypeForExtension: (extension) ->
    switch extension?.toLowerCase()
        when 'glb', 'gltf' then 'gltf'
        when 'nxs', 'nxz' then 'nexus'
        when 'ptm', 'rti' then 'rti'
        else null
```

In `switch/then` in CoffeeScript entspricht `switch/case` in Javascript, allerdings ohne `break`, da CoffeeScript das automatisch macht. Aktuell unterstützte Formate sind:

1. `glb`, `gltf` — Standard-3D-format
2. `nxs`,`nxz` — Nexus-Format für sehr große Dateien
3. `ptm`, `rti` — RTI (Reflectance Transformation Imaging)`

```
modelPriorityForExtension: (extension) ->
    switch extension?.toLowerCase()
        when 'nxs' then 6
        when 'glb' then 5
        when 'nxz', 'gltf' then 4
        when 'ptm' then 3
        when 'rti' then 2
        else null
```

`modelPriorityForExtension` gibt die Priorität einer Asset-Version als Zahl zurück: nxs (6) > glb (5) > nxz/gltf (4) > ptm (3) > rti (2).

## Schritt 7 — URL-Normalisierung mit Access-Token

```
__sameOriginUrl: (rawUrl) ->
    return rawUrl unless rawUrl

    try
        u = new URL(rawUrl, window.location.href)
        if u.origin isnt window.location.origin
            return u.pathname + u.search + u.hash
        return u.href
    catch err
        rawUrl
```

Falls externe URLs zur API nicht zur selben Domain gehören, werden diese in relative Pfade umgewandelt, dadurch werden CORS-Probleme verhindert.

```
__withAccessToken: (rawUrl) ->
    token = ez5?.session?.token
    ...
    u.searchParams.set('access_token', token)
```

Geschützte Assets können zunächst nicht angezeigt werden, weil der Viewer in einem <iframe> läuft und dieser keinen Session-Cookie besitzt. Deshalb wird ein Authentifizierungs-Token benötigt, der mithilfe von __withAccessToken() an die API-URL als Query-Parameter angehängt wird.

## Schritt 8 — Asset-Daten aus fylr auslesen

`__processVersion` prüft eine einzelne Version der Reihe nach auf vier Fälle: ein bereits entpacktes glTF-Archiv, ein bereits entpacktes RTI-Archiv, ein noch nicht entpacktes ZIP, das nur am Dateinamen (.rti.zip) als RTI erkannt wird, und zuletzt die generische Erkennung über die Dateiendung. 

Dafür übersetzt `__processVersion(version, variantFilename = '')` EAS-Daten (EAS = "External Asset Store") einer Version in das interne `assetInfo`-Format:

```
assetInfo =
    type: null
    url: null
    extension: null
    prio: null
```

Sobald ein Fall zutrifft und eine gültige URL liefert, wird sofort zurückgegeben. Das prio-Feld (5 für glTF, 3 für RTI, sonst aus der Lookup-Tabelle) steuert später, welcher Kandidat bei mehreren Treffern gewinnt.

`__easUrl(asset)` durchsucht Asset-Varianten aus EAS-Daten mithilfe von `__processVersion` nach darstellbarem 3D-Modell. Außerdem werden alternative Kandidaten als Fallbacks gesammelt.

`__fetchFullAssetInfo()` fragt die EAS-API gezielt mit der Asset-ID ab und holt vollständige Versionsdaten vom Server nach. Das ist nötig, weil der initiale Kontext, den das Framework übergibt, nicht immer alle Varianten enthält. Der Aufruf liefert ein jQuery-Promise zurück, dessen Ergebnis in `createMarkup()` verarbeitet wird.

## Schritt 9 — Fallback-Mechanismus

```
collectModelUrlCandidates: (value, seen = new WeakSet(), depth = 0, ...) ->
    return results if depth > 7 or not value?
    ...
```

Falls die normale EAS-Datenstruktur kein 3D-Asset findet, durchsucht `collectModelUrlCandidates` rekursiv die gesamte Asset-Datenstruktur nach URLs mit bekannten 3D-Dateiendungen. Maximal 7 Ebenen tief, mit einem `WeakSet` gegen Endlosschleifen bei zirkulären Referenzen.

```
scoreModelCandidate: (candidate) ->
    score += 40 if /(^|\.)(url|href|download|...|original|source)$/.test(pathText)
    score -= 120 if /(preview|poster|thumbnail|...)/.test(pathText)
```

Bewertet gefundene URLs nach Kontext: Ein `url`-Feld in einem `original`-Objekt bekommt mehr Punkte als etwas in einem `thumbnail`-Objekt. So wird verhindert, dass das Plugin versucht, ein Vorschaubild als 3D-Modell zu laden.

`fallbackAssetInfo(asset)` ist das Bindeglied zwischen den beiden Hilfsmethoden: Es ruft `collectModelUrlCandidates` auf, bewertet jeden Treffer mit `scoreModelCandidate` und gibt den besten Kandidaten als fertiges `assetInfo`-Objekt zurück. Findet auch dieser Mechanismus nichts, gibt die Methode `null` zurück und der Viewer startet nicht.

`startAutomatically()` gibt immer `true` zurück und signalisiert dem fylr-Framework, den Viewer direkt beim Anzeigen des Assets zu starten – ohne dass der Nutzer erst einen Button klicken muss.

`getExtension(url)` extrahiert die Dateiendung aus einer URL und ignoriert dabei Query-Parameter und Hash-Fragmente (z.B. liefert `model.glb?token=abc` → `glb`).

## Schritt 10 — Viewer einbetten

`__mountViewer(target, assetInfo)` – das ist der Kern des Plugins:

```
iframe = document.createElement('iframe')
iframe.id = 'threeiframe'
...
pageUrl.searchParams.set('asset', assetInfo?.url or '')
pageUrl.searchParams.set('config', assetInfo.defaults) if assetInfo?.defaults
iframe.src = pageUrl.href
container.appendChild(iframe)
```

Der eigentliche 3D-Viewer läuft in einem <iframe>. Die Asset-URL und eine optionale Konfigurations-URL werden als URL-Parameter übergeben. Das ist die saubere Trennung: das Plugin weiß, wo die Datei liegt – der Viewer in lib/ weiß, wie man sie anzeigt.

`getButtonLocaKey(asset)` entscheidet, ob der Viewer-Button im fylr-Frontend überhaupt angezeigt wird. Gibt es kein erkennbares 3D-Asset (weder per `__easUrl` noch per `fallbackAssetInfo`), gibt die Methode `undefined` zurück – der Button bleibt dann ausgeblendet.

`createViewerContainer(target)` erstellt einen leeren Container mit einem `<canvas>`-Element (für eine direkte, nicht iframe-basierte Viewer-Einbettung). Sie räumt das Ziel-Element vorher leer und setzt eine Mindeshöhe von 480 px.

`createMarkup()` – der Einstiegspunkt, den das fylr-Framework aufruft. Ablauf:
1. Versuche Asset-Info aus den lokalen Daten zu holen (`__easUrl`)
2. Falls nötig: lade vollständige Daten vom Server nach (`__fetchFullAssetInfo`)
3. Dann: `__createMarkup` aufrufen

`__createMarkup()` – finalisiert alles:
1. URLs normalisieren (`__sameOriginUrl`) und Token anhängen (`__withAccessToken`)
2. Ein `<div id="ubhd3d">` erzeugen
3. `__pickFirstAccessible` prüft, welcher Kandidat wirklich erreichbar ist
4. `__mountViewer` bettet den Viewer als `<iframe>` ein


## Schritt 11 — Sortierung und Registrierung

```
sortVariants = (a, b) ->
    if a.prio and b.prio
        b.prio - a.prio
    ...
```

Eine einfache Sortierfunktion (wie `Array.sort((a,b) => b.prio - a.prio)` in JS). Sie steht bewusst außerhalb der Klasse – da sie nur in `__easUrl` verwendet wird und keinen Zugriff auf `this` benötigt, wäre eine Klassenmethode hier überflüssig.

```
ez5.session_ready =>
    AssetBrowser?.plugins?.registerPlugin?(UBHD3DViewerPlugin)
    ez5.pluginManager.getPlugin('fylr-plugin-ubhd-3d-viewer')?.loadCss?()
```

Das Plugin registriert sich erst nach dem Login im fylr-System. `session_ready` ist ein Callback des fylr-Frameworks. `?.registerPlugin?` bedeutet doppelt abgesichert: „falls `registerPlugin` existiert, ruf es auf“. Danach wird das zugehörige CSS geladen.

---

## Gesamtübersicht: Datenfluss

```
fylr-Framework ruft createMarkup() auf
        │
        ▼
__easUrl(): EAS-Varianten nach 3D-Format durchsuchen
        │
        ├─ Asset gefunden? ── Nein ──▶ fallbackAssetInfo(): rekursive Suche
        │                                 │
        └─────────── assetInfo ───────────┘
                          │
          Vollständige Serverdaten nötig?
                 │Ja              │Nein
                 ▼                │
     __fetchFullAssetInfo()       │
     (EAS-API Abfrage)            │
                 └─── assetInfo ──┘
                          │
          URL normalisieren (__sameOriginUrl)
          + Access-Token  (__withAccessToken)
                          │
          __pickFirstAccessible()
          (HTTP HEAD/GET-Check je Kandidat)
                          │
                   __mountViewer()
                          │
          <iframe src="viewer-dist/?asset=URL">
                          │
          Viewer in lib/ übernimmt die Darstellung
```

