# Guía de Compilación y Distribución iOS - AgroVision IA

Esta guía documenta los pasos para compilar, firmar y distribuir la aplicación **AgroVision** para dispositivos iOS (iPhones de Marce y Estanislao) utilizando Xcode o de manera automatizada mediante **Codemagic** para TestFlight.

---

## Método A: Distribución Automatizada vía Codemagic (Recomendado)

Codemagic permite compilar la versión de iOS directamente desde la nube sin necesidad de una Mac local y enviarla a TestFlight, generando notificaciones y códigos QR de descarga.

### Pasos:
1. **Configurar App Store Connect**:
   - Acceda a su panel de desarrollador en Apple Developer.
   - Vaya a **App Store Connect > Users and Access > Integrations > App Store Connect API**.
   - Genere una clave de API de acceso y descargue la clave privada `.p8`. Guarde los valores de `Issuer ID` y `Key ID`.
2. **Subir credenciales a Codemagic**:
   - Conecte su cuenta de Git en [Codemagic](https://codemagic.io/).
   - En la configuración de la aplicación, agregue el grupo de variables `apple_credentials` con:
     - `APP_STORE_CONNECT_API_KEY`: El contenido de su archivo de clave privada `.p8`.
     - `APP_STORE_CONNECT_KEY_ID`: El identificador de clave generado.
     - `APP_STORE_CONNECT_ISSUER_ID`: El Issuer ID de Apple.
     - `APP_STORE_CONNECT_PROJECT_ID`: El ID del proyecto.
3. **Disparar la compilación**:
   - Al realizar un `git push` a la rama `main`, Codemagic leerá automáticamente el archivo [codemagic.yaml](file:///d:/AgroVision_Multiplatform/codemagic.yaml).
   - Compilará la versión de iOS, firmará con sus certificados oficiales de Apple, subirá el compilado (`.ipa`) a **TestFlight** y enviará una notificación a los correos de Marce y Estanislao con el enlace o código QR para su instalación inmediata.

---

## Método B: Compilación Local con Xcode (Requiere Mac)

Si desea compilar directamente desde una computadora Mac o realizar pruebas locales cableadas:

### Prerrequisitos:
- Instalar **Xcode** desde la App Store.
- Instalar **CocoaPods** ejecutando en terminal: `sudo gem install cocoapods`.
- Contar con el SDK de Flutter instalado en la Mac.

### Pasos de Preparación:
1. **Limpiar y obtener dependencias**:
   ```bash
   flutter clean
   flutter pub get
   ```
2. **Generar los pods nativos**:
   ```bash
   cd ios
   pod install
   ```
3. **Abrir el workspace en Xcode**:
   ```bash
   open Runner.xcworkspace
   ```
4. **Configurar Firma en Xcode**:
   - Seleccione el nodo raíz **Runner** en la barra lateral izquierda.
   - Vaya a la pestaña **Signing & Capabilities**.
   - Active **Automatically manage signing** y seleccione su equipo de desarrollo (Apple Developer Account).
   - Cambie el *Bundle Identifier* si es necesario (ej. `com.agrovision.app`).
5. **Compilar y Generar el Archive**:
   - Conecte el iPhone por USB (asegúrese de activar el Modo Desarrollador en el dispositivo en *Ajustes > Privacidad y Seguridad*).
   - En Xcode, seleccione su iPhone como dispositivo destino.
   - Seleccione **Product > Run** para desplegar localmente.
   - Para distribución TestFlight, seleccione **Any iOS Device (arm64)** y presione **Product > Archive**. Luego, siga el asistente de distribución para subirlo a App Store Connect.
