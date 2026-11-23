<!--Hier ist eine ergänzende Übersicht weiterer nützlicher Jellyfin-Plugins mit ihren Use Cases, gefolgt von einer detaillierten Client-Tabelle, sortiert nach deinen Anwendungsfällen.

### 🧩 Weitere nützliche Jellyfin-Plugins & Use Cases

Neben den bereits genannten gibt es noch einige Plugins, die deinen Server in bestimmten Bereichen deutlich aufwerten können.

**Für die Medienverwaltung & Metadaten**
*   **Shokofin (+ Shoko Server)**: Ein unverzichtbares Duo für Anime-Fans. Es identifiziert Anime-Dateien anhand ihres Hashes (unabhängig vom Dateinamen) und löst das Problem der "absoluten Nummerierung" (z.B. Episode 26 statt Staffel 2, Episode 1). Zudem liefert es umfangreiche Metadaten, die von anderen Scrapern oft nicht gefunden werden.
*   **Ani-Sync**: Synchronisiert deinen Sehfortschritt für Anime mit Plattformen wie AniList, MyAnimeList oder Kitsu. So behältst du den Überblick, ohne deine Statistik manuell pflegen zu müssen.
*   **TheIntroDB**: Eine Alternative zu *Intro Skipper*. Statt lokaler Analyse bezieht es die Zeitstempel für Intros, Recap und Abspänne aus einer Community-Datenbank. Das spart Serverressourcen, die Abdeckung kann aber variieren.

**Für Untertitel & Barrierefreiheit**
*   **Subtitle Extract**: Ein offizielles Plugin, das eingebettete Untertitel aus Mediendateien extrahiert und als separate Dateien bereitstellt. Das kann Startverzögerungen bei Clients reduzieren, die mit eingebetteten Untertiteln Probleme haben.
*   **Whisper-subs**: Ein sehr mächtiges Plugin, das Untertitel mithilfe lokaler KI-Modelle (Whisper) generiert, wenn keine Untertiteldatei vorhanden ist. Die gesamte Verarbeitung findet auf deinem eigenen Server statt, es werden keine Daten nach außen gegeben.

**Für Anpassung & Administration**
*   **Skin Manager**: Ermöglicht die einfache Anpassung des Erscheinungsbildes deines Jellyfin-Servers. Es enthält mehrere vorkonfigurierte Themes und erlaubt es dir, eigene CSS-Themes zu erstellen und vor dem Anwenden in einer Vorschau zu testen.
*   **Meilisearch**: Ersetzt die standardmäßige, oft als träge empfundene Suchfunktion von Jellyfin durch die blitzschnelle Suchmaschine Meilisearch. Das macht die Suche in großen Bibliotheken zu einem wesentlich angenehmeren Erlebnis.
-->
### 📱 Client-Übersicht nach Use Case

Die Wahl des richtigen Clients hängt stark vom Gerät und den persönlichen Vorlieben ab. Die folgende Tabelle fasst die wichtigsten Optionen zusammen, sortiert nach dem primären Anwendungsfall.

| Use Case / Gerät | Empfohlene(r) Client(s) | Plattformen | Warum dieser Client? | Wichtige Einschränkung |
| :--- | :--- | :--- | :--- | :--- |
| **Einheitliches Erlebnis (All-Rounder)** | **Moonfin** | Android TV/Fire TV, iOS, tvOS, macOS, Windows, Linux, Roku, Tizen, webOS | Bietet eine konsistente, moderne Oberfläche auf nahezu allen Geräten. Ideal, wenn du überall die gleiche Experience willst. | Die Reife der einzelnen Plattform-Builds kann variieren. |
| **Android TV / Fire TV (Premium)** | **Wholphin** | Android TV, Fire TV | Eine deutliche Steigerung gegenüber der offiziellen App. Bietet eine saubere, auf Fernbedienungen optimierte Oberfläche mit automatischen Empfehlungen, die an Netflix erinnert. | Fokus liegt stark auf der TV-Bedienung. |
| **Android (Smartphone/Tablet)** | **Findroid** | Android | Eine native Android-App, die sich stark auf das Ansehen von Filmen und Serien konzentriert. Die Material-You-Oberfläche fühlt sich sehr poliert an. | Kein vollständiger All-Media-Client (z.B. keine Hörbücher). |
| **Apple-Geräte (Premium)** | **Infuse** | Apple TV, iPhone, iPad, Mac | Die wohl beste Wahl für Apple-Nutzer. Bietet eine herausragende Wiedergabe, breite Formatunterstützung und eine sehr polierte Oberfläche. | Fortgeschrittene Funktionen erfordern die kostenpflichtige Pro-Version. |
| **Apple-Geräte (Offiziell)** | **Swiftfin** | iPhone, iPad, Apple TV | Der offizielle Open-Source-Client des Jellyfin-Projekts. Bietet ein natives Swift-Design und einen Fokus auf Direct Play. | Die Funktionsabdeckung kann je nach Gerät variieren, die Meinungen der Nutzer sind gemischt. |
| **Plattformübergreifend (Mobile)** | **Streamyfin** | iOS, Android | Eine starke Alternative, wenn du einen Video-Client für beide mobilen Plattformen suchst. Bietet Funktionen wie Downloads, Live-TV und Skip-Steuerung. | Musik wird nicht unterstützt, einige Funktionen sind noch experimentell. |
| **Musik (Streaming-Style)** | **Finamp** | Android, iOS | Wenn du deine Musiksammlung mit einer Oberfläche im Stil von Spotify oder Plexamp durchstöbern und abspielen möchtest, ist Finamp die erste Wahl. | Die Qualität hängt stark von den Metadaten deiner Musikdateien ab. |
| **Desktop (Windows/Mac/Linux)** | **Jellyfin Desktop** | Windows, Mac, Linux | Der offizielle Electron-Client des Jellyfin-Projekts. Eine solide, offizielle Option für den Desktop. | Nicht so funktionsreich wie einige der spezialisierten Third-Party-Clients. |
| **Home-Theater (Enthusiast)** | **Kodi + Jellyfin Add-on** | Geräte mit Kodi-Unterstützung | Bietet die tiefste Anpassungsmöglichkeit, Audio-Passthrough und eine extrem mächtige Oberfläche, wenn man bereit ist, Zeit in die Konfiguration zu investieren. | Erfordert die meiste Einrichtungsarbeit. |
<!--
**Zum Schluss noch ein paar Hinweise zur Einordnung:**
*   **Offizielle vs. Third-Party:** Viele der empfohlenen Clients sind Third-Party-Entwicklungen (z.B. Moonfin, Wholphin, Infuse). Diese sind oft funktionsreicher und polierter als die offiziellen Apps, aber ihre Qualität und Update-Frequenz kann variieren.
*   **Direct Play vs. Transcoding:** Clients wie **Infuse** oder **Swiftfin** sind bekannt dafür, viele Formate direkt abspielen zu können (Direct Play), was deinen Server entlastet. Andere Clients müssen eventuell auf Transcoding zurückgreifen.
*   **Die offizielle App als Basis:** Für viele Geräte (Roku, Samsung Tizen, LG webOS) ist die offizielle Jellyfin-App oft die einzige oder zumindest die sicherste Wahl.

Wenn du zu einem bestimmten Client oder Plugin noch Fragen hast, lass es mich wissen.
