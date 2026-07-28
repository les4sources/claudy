# Jeu de pictogrammes du funnel public /reservation.
#
# Pourquoi ce helper existe : le funnel affichait ses repères visuels en emoji
# (📅 🏡 ⛺ 🌿 …). Un emoji est rendu par la police système — il change de dessin,
# de couleur et de chasse selon macOS / Windows / Android, ne suit ni la couleur
# ni la graisse du texte qui l'entoure, et les lecteurs d'écran l'annoncent
# ("calendrier", "maison avec jardin") en plein milieu d'un intitulé. Résultat :
# une première impression qui ne ressemble à rien de tenu, et du bruit vocal.
#
# Ici : des SVG inline 24×24, tracés (`stroke`), `currentColor`, `aria-hidden`.
# Ils héritent de la couleur et de la taille du contexte, sont identiques
# partout, et sont muets pour l'assistance technique — le sens vit dans le texte
# à côté, jamais dans le pictogramme.
#
# Style : Heroicons outline 24 (même langage que les SVG déjà présents dans
# `_stay_calendar.html.slim`), trait 1.5, extrémités arrondies.
module FunnelIconsHelper
  ICON_PATHS = {
    # Dates, calendriers, règles de séjour
    calendar: '<path d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5"/>',
    # Couchage — gîtes, chambres, nuitée individuelle
    bed: '<path d="M3 18v-3.75m0 0a1.5 1.5 0 0 1 1.5-1.5h15a1.5 1.5 0 0 1 1.5 1.5m-18 0V9.75A2.25 2.25 0 0 1 5.25 7.5h13.5A2.25 2.25 0 0 1 21 9.75v4.5m-18 0h18M21 18v-3.75M7.5 11.25h.008v.008H7.5v-.008Z"/>',
    # Groupe, adultes/enfants
    users: '<path d="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z"/>',
    # Animal de compagnie
    paw: '<path d="M8.25 15.75c0-2.07 1.679-3.75 3.75-3.75s3.75 1.68 3.75 3.75c0 1.13-.53 1.98-1.29 2.68-.76.7-1.35 1.57-2.46 1.57s-1.7-.87-2.46-1.57c-.76-.7-1.29-1.55-1.29-2.68Z"/><path d="M7.125 11.25a1.875 1.875 0 1 0 0-3.75 1.875 1.875 0 0 0 0 3.75Zm9.75 0a1.875 1.875 0 1 0 0-3.75 1.875 1.875 0 0 0 0 3.75ZM10.5 7.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm3 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"/>',
    # « De quoi avez-vous envie ? »
    sparkles: '<path d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 0 0-2.456 2.456Z"/>',
    # Gîte
    house: '<path d="m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75"/>',
    # Salles & cuisine pro
    hall: '<path d="M3.75 21h16.5M4.5 21V10.5m15 10.5V10.5M3 10.5h18L12 3 3 10.5ZM8.25 21v-6.75h7.5V21"/>',
    # Camping — tente
    tent: '<path d="M12 4.5 3 21h18L12 4.5Zm0 0v16.5M7.5 21l4.5-8.25L16.5 21"/>',
    # Van / camping-car
    van: '<path d="M8.25 18.75a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m3 0h6m-9 0H3.375a1.125 1.125 0 0 1-1.125-1.125V14.25m17.25 4.5a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m3 0h1.125c.621 0 1.129-.504 1.09-1.124a17.902 17.902 0 0 0-3.213-9.193 2.056 2.056 0 0 0-1.58-.86H14.25M16.5 18.75h-2.25m0-11.177v-.958c0-.568-.422-1.048-.987-1.106a48.554 48.554 0 0 0-10.026 0 1.106 1.106 0 0 0-.987 1.106v7.635m12-6.677v6.677m0 4.5v-4.5m0 0h-12"/>',
    # Repas
    utensils: '<path d="M6.75 3v8.25a2.25 2.25 0 0 0 4.5 0V3M9 11.25V21M4.5 3v4.5M9 3v4.5M17.25 3c-1.243 0-2.25 1.848-2.25 4.125 0 1.98.762 3.632 1.777 4.037.28.111.473.38.473.681V21"/>',
    # Activités, nature
    leaf: '<path d="M4.5 19.5S4.5 9 12 6c4.5-1.8 7.5-1.5 7.5-1.5s.3 3-1.5 7.5c-3 7.5-13.5 7.5-13.5 7.5Zm0 0S9 15 13.5 12"/>',
    # Hamac
    hammock: '<path d="M4 4v16M20 4v16M4 8h16M4 14c4 5 12 5 16 0"/>',
    # Pain & épicerie
    bread: '<path d="M4.5 10.5c0-2.485 3.358-4.5 7.5-4.5s7.5 2.015 7.5 4.5c0 1.06-.61 1.5-1.5 1.5v4.5A1.5 1.5 0 0 1 16.5 18h-9A1.5 1.5 0 0 1 6 16.5V12c-.89 0-1.5-.44-1.5-1.5Zm4.5 1.5v6m3-6v6m3-6v6"/>',
    # Contact, question
    chat: '<path d="M8.625 12a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm3.75 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm3.75 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0ZM12 20.25c4.97 0 9-3.694 9-8.25s-4.03-8.25-9-8.25S3 7.444 3 12c0 2.104.859 4.023 2.273 5.48.432.447.74 1.04.586 1.641a4.483 4.483 0 0 1-.923 1.785A5.969 5.969 0 0 0 6 20.755a5.97 5.97 0 0 0 2.474-.532c.216-.09.463-.11.69-.054A9.03 9.03 0 0 0 12 20.25Z"/>',
    # Avertissement
    alert: '<path d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"/>',
    # Indisponible
    ban: '<path d="M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636"/>',
    # Sélectionné
    check: '<path d="m4.5 12.75 6 6 9-13.5"/>',
    # Navigation
    arrow_right: '<path d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3"/>',
    chevron_down: '<path d="m19.5 8.25-7.5 7.5-7.5-7.5"/>',
    close: '<path d="M6 18 18 6M6 6l12 12"/>',
    # Réassurance paiement
    shield: '<path d="M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z"/>'
  }.freeze

  # `funnel_icon(:tent, class: "w-5 h-5 text-forest")`
  #
  # Toujours décoratif : `aria-hidden="true"` et `focusable="false"` sont posés
  # d'office. Un pictogramme qui porte du sens doit être accompagné d'un texte —
  # visible, ou en `sr-only` pour les cas où la place manque vraiment.
  def funnel_icon(name, css_class: "w-5 h-5", stroke_width: 1.5)
    path = ICON_PATHS[name.to_sym]
    raise ArgumentError, "Pictogramme de funnel inconnu : #{name.inspect}" if path.nil?

    tag.svg(
      raw(path),
      xmlns: "http://www.w3.org/2000/svg",
      fill: "none",
      viewBox: "0 0 24 24",
      "stroke-width": stroke_width,
      stroke: "currentColor",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      class: css_class,
      "aria-hidden": "true",
      focusable: "false"
    )
  end
end
