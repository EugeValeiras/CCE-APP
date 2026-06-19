import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// SVGs vendoreados de icons0.dev (coleccion lucide), tintados via
/// [CceIcon] con el color del [IconTheme] ambiente (currentColor).
abstract final class CceIcons {
  // lucide:house
  static const String allHouse =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></g></svg>';

  // lucide:sofa
  static const String room =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M20 9V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v3"/><path d="M2 16a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5a2 2 0 0 0-4 0v1.5a.5.5 0 0 1-.5.5h-11a.5.5 0 0 1-.5-.5V11a2 2 0 0 0-4 0zm2 2v2m16-2v2M12 4v9"/></g></svg>';

  // lucide:sparkles
  static const String scenes =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594zM20 2v4m2-2h-4"/><circle cx="4" cy="20" r="2"/></g></svg>';

  // lucide:land-plot
  static const String floorPlan =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="m12 8l6-3l-6-3v10"/><path d="m8 11.99l-5.5 3.14a1 1 0 0 0 0 1.74l8.5 4.86a2 2 0 0 0 2 0l8.5-4.86a1 1 0 0 0 0-1.74L16 12m-9.51.85l11.02 6.3m0-6.3L6.5 19.15"/></g></svg>';

  // lucide:lightbulb
  static const String lights =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 14c.2-1 .7-1.7 1.5-2.5c1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5c.7.7 1.3 1.5 1.5 2.5m0 4h6m-5 4h4"/></svg>';

  // lucide:radar
  static const String sensors =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M19.07 4.93A10 10 0 0 0 6.99 3.34M4 6h.01M2.29 9.62a10 10 0 1 0 19.02-1.27"/><path d="M16.24 7.76a6 6 0 1 0-8.01 8.91M12 18h.01m5.98-6.34a6 6 0 0 1-2.22 5.01"/><circle cx="12" cy="12" r="2"/><path d="m13.41 10.59l5.66-5.66"/></g></svg>';

  // lucide:history
  static const String history =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M3 12a9 9 0 1 0 9-9a9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5m4-1v5l4 2"/></g></svg>';

  // lucide:bot
  static const String agent =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2m16 0h2m-7-1v2m-6-2v2"/></g></svg>';

  // lucide:users (sugerencia "¿hay alguien?" / presencia)
  static const String users =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M16 3.128a4 4 0 0 1 0 7.744M22 21v-2a4 4 0 0 0-3-3.87"/><circle cx="9" cy="7" r="4"/></g></svg>';

  // lucide:shield-alert
  static const String alarmShield =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1zm-8-5v4m0 4h.01"/></svg>';

  // lucide:settings
  static const String settings =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0a2.34 2.34 0 0 0 3.319 1.915a2.34 2.34 0 0 1 2.33 4.033a2.34 2.34 0 0 0 0 3.831a2.34 2.34 0 0 1-2.33 4.033a2.34 2.34 0 0 0-3.319 1.915a2.34 2.34 0 0 1-4.659 0a2.34 2.34 0 0 0-3.32-1.915a2.34 2.34 0 0 1-2.33-4.033a2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"/><circle cx="12" cy="12" r="3"/></g></svg>';

  // mynaui:undo (botón "volver" del control remoto: flecha que da la vuelta)
  static const String returnArrow =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M5.636 18.364A9 9 0 1 0 12 3C7.942 3 5.482 5.705 3 8.5"/><path d="M3 4.5v4h4"/></g></svg>';

  // lucide:zap (rail Automatizaciones + estado vacío)
  static const String automations =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/></svg>';

  // lucide:play ("Probar"/"Ejecutar")
  static const String play =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/></svg>';

  // lucide:plus ("+ acción", FAB)
  static const String plus =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14m-7-7v14"/></svg>';

  // lucide:speaker
  static const String speaker =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><rect width="16" height="20" x="4" y="2" rx="2"/><path d="M12 6h.01"/><circle cx="12" cy="14" r="4"/><path d="M12 14h.01"/></g></svg>';

  // lucide:volume-2
  static const String volume2 =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298zM16 9a5 5 0 0 1 0 6m3.364 3.364a9 9 0 0 0 0-12.728"/></svg>';

  // lucide:volume-x
  static const String volumeX =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298zM22 9l-6 6m0-6l6 6"/></svg>';

  // lucide:radio
  static const String radio =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M16.247 7.761a6 6 0 0 1 0 8.478m2.828-11.306a10 10 0 0 1 0 14.134m-14.15 0a10 10 0 0 1 0-14.134m2.828 11.306a6 6 0 0 1 0-8.478"/><circle cx="12" cy="12" r="2"/></g></svg>';

  // lucide:power
  static const String power =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 2v10m6.4-5.4a9 9 0 1 1-12.77.04"/></svg>';

  // lucide:minus
  static const String minus =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14"/></svg>';

  // lucide:trash-2
  static const String trash =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 11v6m4-6v6m5-11v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>';

  // lucide:pencil
  static const String pencil =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497zM15 5l4 4"/></svg>';

  // lucide:chevron-down (grupos expandibles del historial)
  static const String chevronDown =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m6 9l6 6l6-6"/></svg>';

  // lucide:clock (trigger schedule)
  static const String clock =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M12 6v6l4 2"/><circle cx="12" cy="12" r="10"/></g></svg>';

  // lucide:calendar (días)
  static const String calendar =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M8 2v4m8-4v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/></g></svg>';

  // lucide:grip-vertical (reordenar acciones)
  static const String dragHandle =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><circle cx="9" cy="12" r="1"/><circle cx="9" cy="5" r="1"/><circle cx="9" cy="19" r="1"/><circle cx="15" cy="12" r="1"/><circle cx="15" cy="5" r="1"/><circle cx="15" cy="19" r="1"/></g></svg>';

  // lucide:moon (condición "está oscuro")
  static const String moon =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401"/></svg>';

  // lucide:door-open
  static const String doorOpen =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 20H2m9-15.438v16.157a1 1 0 0 0 1.242.97L19 20V5.562a2 2 0 0 0-1.515-1.94l-4-1A2 2 0 0 0 11 4.561zM11 4H8a2 2 0 0 0-2 2v14m8-8h.01M22 20h-3"/></svg>';

  // lucide:check (estado éxito / selección)
  static const String check =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 6L9 17l-5-5"/></svg>';

  // lucide:pointer (trigger manual / botón)
  static const String handTap =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M22 14a8 8 0 0 1-8 8m4-11v-1a2 2 0 0 0-2-2a2 2 0 0 0-2 2m0 0V9a2 2 0 0 0-2-2a2 2 0 0 0-2 2v1m0-.5V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v10"/><path d="M18 11a2 2 0 1 1 4 0v3a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15"/></g></svg>';

  // ── JBL remote (icons0.dev / lucide) ───────────────────────────────────────

  // lucide:tv
  static const String tv =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="m17 2l-5 5l-5-5"/><rect width="20" height="15" x="2" y="7" rx="2"/></g></svg>';

  // lucide:layout-grid (botón ancho de apps del TV)
  static const String appsGrid =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/></g></svg>';

  // simple-icons:samsung (logo de marca para la card del TV)
  static const String samsung =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="currentColor" d="m19.817 10.28l.046 2.694h-.023l-.78-2.693h-1.283v3.392h.848l-.046-2.785h.023l.836 2.785h1.227v-3.392zm-16.15 0l-.641 3.428h.928l.47-3.118h.023l.459 3.118h.916l-.63-3.427zm5.181 0l-.424 2.614h-.023l-.424-2.613H6.58l-.069 3.427h.86l.023-3.083h.011l.573 3.083h.871l.573-3.083h.023l.023 3.083h.86l-.08-3.427zm-7.266 2.454a.5.5 0 0 1 .011.252c-.023.114-.103.229-.332.229c-.218 0-.344-.126-.344-.31v-.332H0v.264c0 .768.607.997 1.25.997c.618 0 1.134-.218 1.214-.78c.046-.298.012-.492 0-.561c-.16-.722-1.467-.929-1.559-1.33a.5.5 0 0 1 0-.183c.023-.115.104-.23.31-.23s.32.127.32.31v.206h.86v-.24c0-.745-.676-.86-1.157-.86c-.608 0-1.112.206-1.204.757a1.04 1.04 0 0 0 .012.458c.137.71 1.364.917 1.536 1.352m11.152 0c.034.08.022.184.011.253c-.023.114-.103.229-.332.229c-.218 0-.344-.126-.344-.31v-.332h-.917v.264c0 .756.596.985 1.238.985c.619 0 1.123-.206 1.203-.779c.046-.298.012-.481 0-.562c-.137-.71-1.433-.928-1.524-1.318a.5.5 0 0 1 0-.183c.023-.115.103-.23.31-.23c.194 0 .32.127.32.31v.206h.848v-.24c0-.745-.665-.86-1.146-.86c-.607 0-1.1.195-1.192.757c-.023.149-.023.286.012.458c.137.71 1.34.905 1.513 1.352m2.888.459c.24 0 .31-.16.332-.252c.012-.035.012-.092.012-.126V10.28h.87v2.464c0 .069 0 .195-.01.23c-.058.641-.562.847-1.193.847c-.63 0-1.134-.206-1.192-.848c0-.034-.011-.16-.011-.229V10.28h.87v2.533c0 .046 0 .091.012.126c0 .091.07.252.31.252m7.152-.034c.252 0 .332-.16.355-.253c.011-.034.011-.091.011-.126v-.493h-.355v-.504H24v.917c0 .069 0 .115-.011.23c-.058.63-.597.847-1.204.847s-1.146-.217-1.203-.848c-.012-.114-.012-.16-.012-.229v-1.444c0-.057.012-.172.012-.23c.08-.641.596-.847 1.203-.847s1.135.206 1.203.848c.012.103.012.229.012.229v.115h-.86v-.195s0-.08-.011-.126c-.012-.08-.08-.252-.344-.252c-.252 0-.32.16-.344.252c-.011.045-.011.103-.011.16v1.57c0 .046 0 .092.011.126c0 .092.092.253.333.253"/></svg>';

  // lucide:cable (HDMI)
  static const String hdmi =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M17 19a1 1 0 0 1-1-1v-2a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2a1 1 0 0 1-1 1zm0 2v-2"/><path d="M19 14V6.5a1 1 0 0 0-7 0v11a1 1 0 0 1-7 0V10m16 11v-2M3 5V3"/><path d="M4 10a2 2 0 0 1-2-2V6a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2a2 2 0 0 1-2 2zm3-5V3"/></g></svg>';

  // lucide:bluetooth
  static const String bluetooth =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m7 7l10 10l-5 5V2l5 5L7 17"/></svg>';

  // lucide:audio-lines (ATMOS)
  static const String atmos =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2 10v3m4-7v11m4-14v18m4-13v7m4-10v13m4-8v3"/></svg>';

  // lucide:waves (BASS)
  static const String bass =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2 6c.6.5 1.2 1 2.5 1C7 7 7 5 9.5 5c2.6 0 2.4 2 5 2c2.5 0 2.5-2 5-2c1.3 0 1.9.5 2.5 1M2 12c.6.5 1.2 1 2.5 1c2.5 0 2.5-2 5-2c2.6 0 2.4 2 5 2c2.5 0 2.5-2 5-2c1.3 0 1.9.5 2.5 1M2 18c.6.5 1.2 1 2.5 1c2.5 0 2.5-2 5-2c2.6 0 2.4 2 5 2c2.5 0 2.5-2 5-2c1.3 0 1.9.5 2.5 1"/></svg>';

  // lucide:gauge (CALIBR)
  static const String calibrate =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m12 14l4-4M3.34 19a10 10 0 1 1 17.32 0"/></svg>';

  // lucide:radio-tower (Surround)
  static const String surround =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M4.9 16.1C1 12.2 1 5.8 4.9 1.9m2.9 2.8a6.14 6.14 0 0 0-.8 7.5"/><circle cx="12" cy="9" r="2"/><path d="M16.2 4.8c2 2 2.26 5.11.8 7.47M19.1 1.9a9.96 9.96 0 0 1 0 14.1m-9.6 2h5M8 22l4-11l4 11"/></g></svg>';

  // lucide:heart (favorito)
  static const String heart =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2 9.5a5.5 5.5 0 0 1 9.591-3.676a.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5"/></svg>';

  // simple-icons:jbl (wordmark del AppBar de Sonido)
  static const String jbl =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="currentColor" d="m0 5.265l2.022 4.589l2.022-4.59zm2.022 7.6c.698 0 1.266-.565 1.266-1.26c0-.699-.568-1.262-1.266-1.262a1.262 1.262 0 1 0 0 2.523M.928 16.228c0 .957.862 2.509 3.315 2.509s3.315-1.188 3.315-2.51V5.266H5.369l.001 11.342c0 .62-.503 1.14-1.126 1.14a1.127 1.127 0 0 1-1.128-1.124l-.001-2.311H.928zm8.289 2.311V5.265h4.374c.845 0 2.187.693 2.187 2.162v2.261c0 .662-.58 1.833-1.44 1.833c.86 0 1.44.742 1.44 1.305v3.979c0 .676-.546 1.733-2.187 1.733zm3.38-7.559c.796 0 .995-.134.995-2.214s-.2-2.246-.995-2.246h-1.195v4.457zm.995 3.811c0-2.081 0-2.69-.864-2.69h-1.326v5.348l1.326.003c.863 0 .863-.581.863-2.66m3.779 3.748H24v-4.226h-2.189l.002 2.31a1.126 1.126 0 0 1-2.255 0V5.265H17.37Z"/></svg>';

  // lucide:x (cerrar — chip del top bar)
  static const String close =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 6L6 18M6 6l12 12"/></svg>';

  // lucide:sun (brillo — botón circular)
  static const String sun =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.93 4.93l1.41 1.41m11.32 11.32l1.41 1.41M2 12h2m16 0h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></g></svg>';

  // ── Termostato (icons0.dev / lucide) ───────────────────────────────────────

  // lucide:thermometer (temperatura actual / setpoint)
  static const String thermometer =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0"/></svg>';

  // lucide:flame (modo calor)
  static const String flame =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3q1 4 4 6.5t3 5.5a1 1 0 0 1-14 0a5 5 0 0 1 1-3a1 1 0 0 0 5 0c0-2-1.5-3-1.5-5q0-2 2.5-4"/></svg>';

  // lucide:snowflake (modo frío)
  static const String snowflake =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="m10 20l-1.25-2.5L6 18m4-14L8.75 6.5L6 6m8 14l1.25-2.5L18 18M14 4l1.25 2.5L18 6"/><path d="m17 21l-3-6h-4m7-12l-3 6l1.5 3M2 12h6.5L10 9m10 1l-1.5 2l1.5 2"/><path d="M22 12h-6.5L14 15M4 10l1.5 2L4 14m3 7l3-6l-1.5-3M7 3l3 6h4"/></g></svg>';

  // ── Cerradura (icons0.dev / CoreUI Free) ───────────────────────────────────

  // lucide:lock-keyhole (cerrada) — viewBox 0 0 24 24 (el cil:lock anterior
  // tenía viewBox 512 con width/height 24: ese mismatch hacía que en iOS/Impeller
  // SvgPicture lo renderizara GIGANTE a pantalla completa = el "candado gigante").
  static const String lockLocked =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><circle cx="12" cy="16" r="1"/><rect width="18" height="12" x="3" y="10" rx="2"/><path d="M7 10V7a5 5 0 0 1 10 0v3"/></g></svg>';

  // lucide:lock-keyhole-open (abierta) — viewBox 0 0 24 24 (ver nota arriba).
  static const String lockUnlocked =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><circle cx="12" cy="16" r="1"/><rect width="18" height="12" x="3" y="10" rx="2"/><path d="M7 10V7a5 5 0 0 1 9.33-2.5"/></g></svg>';

  // lucide:battery-warning (badge batería baja en el plano)
  static const String batteryWarning =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 17h.01M10 7v6m4-7h2a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2m8-4v-4M6 18H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h2"/></svg>';
}

/// Tokens del relieve neumorfico ("hoja que sobresale"): luz arriba-izquierda
/// + sombra abajo-derecha. UNA sola fuente de verdad, compartida por [CceIcon]
/// (ghost SVG) y el IconTheme global de `CceTheme` (Icon de Material/Mdi), para
/// que ambas tecnicas converjan en el mismo relieve app-wide.
abstract final class CceEmboss {
  /// Sombra proyectada abajo-derecha (da el volumen).
  static const Shadow shadow = Shadow(
    color: Color(0xCC05060A),
    offset: Offset(1.3, 2.2),
    blurRadius: 2.0,
  );

  /// Realce tenue arriba-izquierda (luz neumorfica).
  static const Shadow highlight = Shadow(
    color: Color(0x1FFFFFFF),
    offset: Offset(-1.1, -1.4),
    blurRadius: 1.1,
  );

  /// Lista lista para `IconThemeData.shadows` / `Icon.shadows` (Material/Mdi).
  static const List<Shadow> iconShadows = [shadow, highlight];

  /// Por debajo de este tamano el ghost-blur ensucia el glyph -> sin emboss.
  static const double minSize = 18.0;
}

/// Relieve "extruido" de un glyph (icono) SIN circulo de fondo, con colores de
/// luz/sombra ARBITRARIOS (no fijos como [CceEmboss]) para que el relieve se
/// lea como MOLDEADO de la superficie sobre la que va: sobre neoBase (oscuro)
/// usa el par fijo de [CceEmboss]; sobre un fill de color pastel (room card ON)
/// se le inyectan highlight = tono mas claro del color + shadow = tono mas
/// oscuro del color, derivados via [surfaceEmboss], de modo que el canto de luz
/// y la sombra deriven del COLOR de la card (no blanco/negro puros) y NO
/// ensucien el glyph.
///
/// Funciona con CUALQUIER widget hijo (anda con [CceIcon] SVG y con el `Icon`
/// de Material), porque usa la misma tecnica "ghost" (2 copias recoloreadas +
/// desenfocadas detras del glyph real, via ColorFiltered srcATop + ImageFiltered
/// blur). Centraliza el TAMANO con SizedBox+FittedBox(BoxFit.contain), asi
/// ambos tipos de icono terminan al mismo tamano visual sin importar su `size`
/// intrinseco (CceIcon ignora IconTheme.size; el Icon de Material lo hereda).
///
/// Aplana al hijo (IconTheme color + shadows: const []) para que NO sume su
/// propio relieve por debajo del ghost (doble emboss = halo sucio). El color
/// del glyph se reimpone via [color]. Envuelto en RepaintBoundary y Clip.none,
/// limitado a 2 capas de blur (mismo coste que [CceIcon._ghost]).
class EmbossedGlyph extends StatelessWidget {
  const EmbossedGlyph({
    super.key,
    required this.child,
    required this.size,
    required this.color,
    required this.highlight,
    required this.shadow,
    this.highlightOffset = const Offset(-1.1, -1.4),
    this.shadowOffset = const Offset(1.3, 2.2),
    this.blur = 1.6,
  });

  /// El icono a extruir (CceIcon SVG o Icon de Material). Se aplana y recolorea.
  final Widget child;

  /// Tamano visual final del glyph (cuadrado size x size). "Bien grande".
  final double size;

  /// Color del glyph real (contraste contra la superficie bajo el icono).
  final Color color;

  /// Canto de luz (arriba-izquierda). En ON deriva del color de la card.
  final Color highlight;

  /// Sombra (abajo-derecha). En ON deriva del color de la card.
  final Color shadow;

  final Offset highlightOffset;
  final Offset shadowOffset;
  final double blur;

  /// Fija el hijo a [color] y lo APLANA (shadows: const []) para que no sume
  /// su propio relieve ni use IconTheme.size del ancestro: queda como base
  /// plana lista para el ghost. FittedBox lo lleva a [size] sin importar su
  /// tamano intrinseco (24 de CceIcon, 22 heredado del Icon, etc.).
  Widget _flat() {
    return IconTheme.merge(
      data: IconThemeData(color: color, size: size, shadows: const <Shadow>[]),
      child: SizedBox.square(
        dimension: size,
        child: FittedBox(fit: BoxFit.contain, child: child),
      ),
    );
  }

  /// Copia recoloreada+desenfocada+desplazada detras del glyph real ("ghost").
  Widget _ghost(Color tint, Offset off) {
    return Transform.translate(
      offset: off,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(tint, BlendMode.srcATop),
          child: _flat(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Glyph chico: el blur ensuciaria -> solo base plana, sin emboss.
    if (size < CceEmboss.minSize) return _flat();
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            _ghost(shadow, shadowOffset),
            _ghost(highlight, highlightOffset),
            _flat(),
          ],
        ),
      ),
    );
  }

  /// Deriva el par (highlight, shadow) de una superficie de color: luz = el
  /// color mas claro (HSL L+0.18), sombra = el color mas oscuro (HSL L-0.22).
  /// Asi el relieve es "moldeado" del material de la card en vez de blanco/negro
  /// puros (que sobre un pastel claro lavarian/ensuciarian el glyph). El alpha
  /// modula cuanto del relieve se ve (calibrable por estado).
  static (Color, Color) surfaceEmboss(
    Color surface, {
    double lightAlpha = 0.85,
    double shadowAlpha = 0.55,
  }) {
    final hsl = HSLColor.fromColor(surface);
    final light = hsl
        .withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: lightAlpha);
    final dark = hsl
        .withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: shadowAlpha);
    return (light, dark);
  }
}

/// Renderiza un SVG de [CceIcons] tintado, con relieve neumorfico por defecto
/// (el glyph sobresale: realce arriba-izquierda + sombra abajo-derecha,
/// tecnica "ghost" = 2 copias tintadas+desenfocadas detras del glyph real).
///
/// Si no se pasa [color], usa el color del IconTheme ambiente, para que
/// NavigationBar/NavigationRail tinten correctamente los estados
/// selected/unselected.
///
/// El emboss se desactiva automaticamente para [size] < [CceEmboss.minSize]
/// (glifos chicos donde el blur ensucia) o pasando `emboss: false` (util para
/// iconos blancos sobre fills de color saturado, logos, o chrome). El
/// constructor sigue siendo `const`, asi que los call-sites `const CceIcon(...)`
/// no se rompen.
class CceIcon extends StatelessWidget {
  const CceIcon(
    this.svg, {
    super.key,
    this.size = 24,
    this.color,
    this.emboss = true,
  });

  final String svg;
  final double size;
  final Color? color;

  /// Opt-out del relieve neumorfico. Default true (auto-emboss app-wide).
  final bool emboss;

  /// El SVG tintado con [tint] (o el color ambiente si [tint] es null).
  ///
  /// BLINDAJE: el SVG va SIEMPRE envuelto en un `SizedBox.square(size)` ademas
  /// de pasarle width/height a SvgPicture. Asi el glyph queda acotado a
  /// `size x size` de LAYOUT aunque el padre pase constraints sueltas/infinitas
  /// (Stack sin Positioned, Row/Column sin tamano, FittedBox) o aunque una
  /// version futura de flutter_svg cambie su auto-bounding: es imposible que el
  /// candado se expanda a tamano pantalla.
  Widget _raw(Color? tint) {
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.string(
        svg,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter:
            tint != null ? ColorFilter.mode(tint, BlendMode.srcIn) : null,
      ),
    );
  }

  /// Copia tintada+desenfocada y desplazada detras del glyph real ("ghost").
  Widget _ghost(Color tint, Offset off, double blur) {
    return Transform.translate(
      offset: off,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(tint, BlendMode.srcATop),
          child: _raw(tint),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final c = color ?? iconTheme.color;
    final base = _raw(c);

    // Senal de aplanado del ambiente: si un ancestro fija `shadows: []` en su
    // IconTheme (p.ej. el badge de RoomCard sobre fill tintado, donde el
    // relieve ensuciaria el halo), CceIcon se aplana igual que el Icon de
    // Material -> UN solo mecanismo de opt-out flatten para ambas tecnicas.
    final ambientFlat =
        iconTheme.shadows != null && iconTheme.shadows!.isEmpty;

    // Sin emboss: glifo chico, opt-out explicito, ambiente aplanado, o sin
    // color resoluble.
    if (!emboss || ambientFlat || size < CceEmboss.minSize || c == null) {
      return base;
    }

    // RepaintBoundary: aisla las 3 capas (caro: 2 ImageFilter.blur) del
    // repaint del resto de la lista/card en scroll y animaciones de glow.
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            _ghost(
              CceEmboss.shadow.color,
              CceEmboss.shadow.offset,
              CceEmboss.shadow.blurRadius,
            ),
            _ghost(
              CceEmboss.highlight.color,
              CceEmboss.highlight.offset,
              CceEmboss.highlight.blurRadius,
            ),
            base,
          ],
        ),
      ),
    );
  }
}
