# Nouvelle interface (redesign, Michael 2026-10-24) : la barre latérale, la
# barre du haut et les onglets du téléphone lisent TOUS la même liste,
# `interface_nav_groups`. Une entrée ajoutée ici apparaît partout, avec le même
# droit d'accès que l'ancienne barre.
module InterfaceHelper
  # Pictogrammes au trait (famille Lucide), dessinés en `currentColor`.
  ICONS = {
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    bed: '<path d="M2 4v16M2 8h18a2 2 0 0 1 2 2v10M2 17h20M6 8v9"/>',
    chef: '<path d="M17 21a1 1 0 0 0 1-1v-5.35c0-.457.316-.844.727-1.041a4 4 0 0 0-2.134-7.589 5 5 0 0 0-9.186 0 4 4 0 0 0-2.134 7.588c.411.198.727.585.727 1.041V20a1 1 0 0 0 1 1Z"/><path d="M6 17h12"/>',
    utensils: '<path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2M7 2v20M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"/>',
    compass: '<circle cx="12" cy="12" r="10"/><path d="m16.24 7.76-2.12 6.36-6.36 2.12 2.12-6.36z"/>',
    brief: '<path d="M16 20V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/><rect x="2" y="6" width="20" height="14" rx="2"/>',
    cycle: '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
    users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    guide: '<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>',
    map: '<path d="M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z"/><path d="M15 5.764v15M9 3.236v15"/>',
    wallet: '<path d="M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1"/><path d="M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4"/>',
    book: '<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20"/>',
    receipt: '<path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8M12 17.5v-11"/>',
    home: '<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M9 22V12h6v10"/>',
    clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    sliders: '<path d="M21 4h-7M10 4H3M21 12h-9M8 12H3M21 20h-5M12 20H3M14 2v4M8 10v4M16 18v4"/>',
    grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    right: '<path d="m9 18 6-6-6-6"/>',
    plus: '<path d="M5 12h14M12 5v14"/>',
    in: '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M15 12H3"/>',
    out: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
    room: '<path d="M2 3h20M21 3v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V3M7 21l5-5 5 5"/>',
    star: '<path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01z"/>',
    moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
    phone: '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
    swap: '<path d="m16 3 4 4-4 4M20 7H4M8 21l-4-4 4-4M4 17h16"/>',
    bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
    fold: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18M16 15l-3-3 3-3"/>',
    unfold: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18M14 9l3 3-3 3"/>'
  }.freeze

  # Statut d'un séjour, d'une demande… : une FORME et un mot, la couleur ne fait
  # que confirmer (pointillé = en attente, demi-plein = pré-confirmé, plein coché
  # = confirmé, barré = annulé, triangle = à faire, carré = refusé).
  STATUS_SHAPES = {
    wait: '<circle cx="6" cy="6" r="4.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="2.2 1.6"/>',
    pre: '<circle cx="6" cy="6" r="4.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M6 1.5a4.5 4.5 0 0 1 0 9z" fill="currentColor"/>',
    ok: '<circle cx="6" cy="6" r="5.5" fill="currentColor"/><path d="M3.6 6.2l1.6 1.6 3.2-3.4" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
    off: '<circle cx="6" cy="6" r="4.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M3 9 9 3" stroke="currentColor" stroke-width="1.6"/>',
    todo: '<path d="M6 1 11 10H1z" fill="currentColor"/><path d="M6 4.5v2.5" stroke="#fcf4cc" stroke-width="1.4" stroke-linecap="round"/><circle cx="6" cy="8.6" r=".8" fill="#fcf4cc"/>',
    no: '<rect x="1" y="1" width="10" height="10" rx="2.5" fill="currentColor"/><path d="M4 4l4 4M8 4 4 8" stroke="#fbe6e2" stroke-width="1.5" stroke-linecap="round"/>'
  }.freeze

  # Sans Warden (previews Lookbook, rendus hors requête), pas de compte : on reste
  # dans l'ancienne interface.
  def new_interface?
    return false if request.nil? || request.env["warden"].nil?

    current_user&.new_interface? || false
  end

  # La porte d'entrée de la nouvelle interface : « Aujourd'hui » pour qui voit
  # l'agenda, sinon la première page que son rôle ouvre.
  def today_or_home_path
    section_readable?(:calendar) ? today_path : (access_home_path || dashboard_path)
  end

  # Barre latérale repliée en icônes (Michael 2026-10-24) : un choix de
  # navigateur, gardé dans un cookie pour que la page arrive déjà repliée,
  # sans saut au chargement. Voir `ui_side_controller.js`.
  SIDE_COOKIE = "ui_side"

  def ui_side_collapsed?
    cookies[SIDE_COOKIE] == "collapsed"
  end

  # L'infobulle d'une entrée : son nom, et ce qui l'attend.
  def ui_nav_tip(entry)
    [entry[:label], ("#{entry[:count]} à traiter" if entry[:count])].compact.join(" · ")
  end

  def ui_icon(name, size: 20, css: nil)
    content_tag(:svg, ICONS.fetch(name.to_sym).html_safe,
                class: ["ui-ico", css].compact.join(" "), width: size, height: size, viewBox: "0 0 24 24",
                fill: "none", stroke: "currentColor", "stroke-width": 1.75, "stroke-linecap": "round",
                "stroke-linejoin": "round", "aria-hidden": "true")
  end

  def ui_status(kind, label)
    content_tag(:span, class: "ui-st ui-st-#{kind}") do
      content_tag(:svg, STATUS_SHAPES.fetch(kind.to_sym).html_safe, viewBox: "0 0 12 12", "aria-hidden": "true") + label
    end
  end

  # Avatar en ARCHE, la forme du logo des 4 Sources : la photo de la fiche
  # humain quand il y en a une (`Human#photo`, comme le Guide et les
  # commentaires), sinon les initiales sur une teinte du DS.
  def ui_avatar(name, tone: nil, small: false, human: nil)
    classes = "ui-av#{' ui-av-s' if small}"
    if human.respond_to?(:photo?) && human.photo?
      return image_tag(human.photo_url(:thumb), alt: "", class: "#{classes} ui-av-photo", "aria-hidden": "true")
    end

    initials = name.to_s.split(/[\s-]+/).first(2).map { |part| part[0] }.join.upcase.presence || "?"
    tone ||= %w[o g b y sand][name.to_s.sum % 5]
    content_tag(:span, initials, class: "#{classes} ui-av-#{tone}", "aria-hidden": "true")
  end

  # Groupes de la barre latérale : [libellé, [entrées]]. Une entrée :
  # { key:, label:, icon:, path:, count: }. Seules les entrées que le compte peut
  # ouvrir sont gardées ; un groupe vide disparaît.
  def interface_nav_groups
    @interface_nav_groups ||= [
      ["Au quotidien", [
        nav_entry(:today, "Aujourd’hui", :sun, today_path, section_readable?(:calendar)),
        nav_entry(:agenda, "Agenda", :calendar, root_path, section_readable?(:calendar)),
        nav_entry(:stays, "Séjours", :bed, stays_path, section_readable?(:full), count: -> { Stay.where(status: "pending").where("departure_date IS NULL OR departure_date >= ?", Date.current).count }),
        nav_entry(:kitchen, "Cuisine", :chef, kitchen_orders_path, section_readable?(:full), count: -> { MealOrder.pending_validation.upcoming.count }),
        nav_entry(:activities, "Activités", :compass, experience_bookings_path, section_readable?(:events), count: -> { ExperienceBooking.pending.with_visible_stay.count }),
        nav_entry(:coworking, "Coworking", :brief, coworking_packs_path, section_readable?(:full))
      ]],
      ["Le collectif", [
        nav_entry(:cycles, "Cycles", :cycle, organisation_path, section_readable?(:full)),
        nav_entry(:gatherings, "Rassemblements", :users, gatherings_path, section_readable?(:full)),
        nav_entry(:projects, "Projets", :folder, projects_path, section_readable?(:full)),
        nav_entry(:guide, "Guide", :guide, guide_root_path, guide_readable?),
        nav_entry(:map, "Carte du domaine", :map, map_path, section_readable?(:map))
      ]],
      ["Argent", [
        nav_entry(:accounts, "Comptes", :wallet, finance_accounts_path, section_readable?(:accounts)),
        nav_entry(:accounting, "Comptabilité", :book, finance_accounting_path, section_readable?(:accounting)),
        nav_entry(:invoicing, "Facturation", :receipt, invoicing_path, section_readable?(:full))
      ]]
    ].map { |label, entries| [label, entries.compact] }.reject { |_, entries| entries.empty? }
  end

  # Pied de la barre latérale : les consultations ponctuelles.
  def interface_nav_footer
    [
      nav_entry(:dashboard, "Mon tableau de bord", :home, dashboard_path, section_readable?(:everyone)),
      nav_entry(:activity, "Activité récente", :clock, recent_activity_path, section_readable?(:full)),
      nav_entry(:settings, "Paramètres", :sliders, experiences_path, section_readable?(:full) || section_readable?(:events))
    ].compact
  end

  # Les quatre onglets du téléphone ; tout le reste passe dans « Plus ».
  TAB_KEYS = %i[today agenda stays kitchen].freeze

  def interface_tabs
    entries = interface_nav_groups.flat_map(&:last)
    TAB_KEYS.filter_map { |key| entries.find { |entry| entry[:key] == key } }
  end

  def interface_more_entries
    (interface_nav_groups.flat_map(&:last) + interface_nav_footer).reject { |entry| TAB_KEYS.include?(entry[:key]) }
  end

  def interface_current?(key)
    interface_current_key == key
  end

  # L'écran où l'on se trouve, en clé de navigation. Les drapeaux `@*_view`
  # sont ceux que pose déjà chaque contrôleur pour l'ancienne barre.
  def interface_current_key
    @interface_current_key ||=
      if controller_name == "pages" && action_name == "today" then :today
      elsif controller_name == "pages" && action_name == "calendar" then :agenda
      elsif controller_name == "pages" && action_name == "dashboard" then :dashboard
      elsif action_name == "recent_activity" then :activity
      elsif controller_path.start_with?("kitchen/orders", "kitchen/reporting") then :kitchen
      elsif controller_name.start_with?("coworking") then :coworking
      elsif controller_name == "invoicing" then :invoicing
      elsif controller_name == "experience_bookings" then :activities
      elsif controller_name == "gatherings" then :gatherings
      elsif %w[projects tasks bundles].include?(controller_name) then :projects
      elsif @map_view then :map
      elsif @guide_view then :guide
      elsif @accounting_view then :accounting
      elsif @finance_view then :accounts
      elsif @organisation_view then :cycles
      elsif @settings_view then :settings
      elsif @home_view then :stays
      end
  end

  def interface_page_title
    entry = (interface_nav_groups.flat_map(&:last) + interface_nav_footer).find { |e| e[:key] == interface_current_key }
    entry ? entry[:label] : "Claudy"
  end

  private

  def nav_entry(key, label, icon, path, allowed, count: nil)
    return nil unless allowed

    value = count&.call.to_i
    { key: key, label: label, icon: icon, path: path, count: value.to_i.positive? ? value : nil }
  end
end
