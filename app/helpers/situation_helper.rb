# La Situation financière (Michael, 2026-11-12) est lue par les Sourciers, la
# Comptabilité ouverte aux seuls Administratifs. Un lien de la Situation vers un
# écran de compta n'est donc un lien que pour qui peut l'ouvrir ; pour les
# autres, le même texte, sans porte qui mène à « Tu n'as pas accès ».
module SituationHelper
  # Même signature que `link_to`, bloc compris. `nav: true` pour un lien qui
  # n'est qu'une porte (« Trésorerie », « Ouvrir la file ») : sans accès, il
  # disparaît au lieu de laisser un texte qui ressemble à un lien.
  def situation_link_to(name = nil, options = nil, html_options = nil, &block)
    if block
      html_options = options
      options = name
      name = nil
    end
    html_options = (html_options || {}).dup
    nav_only = html_options.delete(:nav)
    return link_to(name, options, html_options, &block) if section_readable?(:accounting)
    return nil if nav_only

    content = block ? capture(&block) : name
    css = html_options[:class].to_s.split.reject { |c| c == "ui-card-link" || c.start_with?("text-blue", "hover:") }.join(" ")
    content_tag(:span, content, class: css.presence)
  end

  # Le lien « Voir » d'un signal : la Situation s'ouvre à tous ses lecteurs,
  # le reste (trésorerie comprise) seulement à qui lit la Comptabilité.
  def situation_signal_path(signal)
    path = signal.path
    return nil if path.blank?
    return path if section_readable?(:accounting)

    path.start_with?("/finance/situation") ? path : nil
  end
end
