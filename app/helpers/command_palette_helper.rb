# Les écrans et les actions de la palette ⌘K (redesign, Michael 2026-10-29).
# Les écrans sont ceux de la barre latérale (`interface_nav_groups`, donc déjà
# filtrés par les droits) et, pour qui lit la Comptabilité, ses sous-écrans
# (`AccountingNavHelper`) : « CODA » ou « Grand livre » se trouvent en tapant
# leur nom. Les données (séjours, personnes, Guide) viennent de
# `CommandPalette::Search`.
module CommandPaletteHelper
  SCREEN_LIMIT = 6

  # [{ label:, hint:, icon:, path: }] ; sans requête, les écrans de la barre.
  def command_screens(query)
    screens = interface_nav_groups.flat_map(&:last).map { |e| { label: e[:label], hint: nil, icon: e[:icon], path: e[:path] } }
    screens += interface_nav_footer.map { |e| { label: e[:label], hint: nil, icon: e[:icon], path: e[:path] } }
    if section_readable?(:accounting)
      accounting = accounting_nav_direct + accounting_nav_groups.flat_map(&:last) + [accounting_nav_guide]
      screens += accounting.map do |label, path, _|
        { label: label == "Guide" ? "Guide de la comptabilité" : label, hint: accounting_nav_hint(label), icon: :book, path: path }
      end
    end
    screens = screens.uniq { |screen| screen[:path] }
    return screens.first(SCREEN_LIMIT) if query.blank?

    screens.select { |screen| command_match?(query, screen[:label], screen[:hint]) }.first(SCREEN_LIMIT)
  end

  # Les gestes les plus fréquents, selon les droits d'écriture. « Nouveau
  # séjour pour Claire Dubois » quand la recherche a trouvé un client.
  def command_actions(query, customer: nil)
    actions = []
    if section_writable?(:full)
      actions << { label: "Nouveau séjour pour #{customer.name}", path: new_stay_path(customer_id: customer.id), icon: :plus } if customer
      actions << { label: "Nouveau séjour", path: new_stay_path, icon: :plus }
      actions << { label: "Nouvelle demande en cuisine", path: new_kitchen_order_path, icon: :chef }
    end
    if section_writable?(:accounting)
      actions << { label: "Compter la caisse", path: new_finance_cash_count_path, icon: :wallet }
      actions << { label: "Nouvelle note de frais", path: new_finance_expense_report_path(kind: "expenses", human_id: current_user.linked_human&.id), icon: :receipt }
    end
    return actions if query.blank?

    actions.select { |action| action[:label].start_with?("Nouveau séjour pour") || command_match?(query, action[:label]) }
  end

  # Chaque mot tapé se retrouve dans le libellé ou sa ligne d'aide, sans
  # casse ni accents : « grand liv », « coda », « note frais ».
  def command_match?(query, *texts)
    haystack = command_fold(texts.compact.join(" "))
    command_fold(query).split.all? { |word| haystack.include?(word) }
  end

  # Le terme cherché, surligné dans un libellé (sans casse ni accents).
  def command_highlight(text, query)
    text = text.to_s
    words = command_fold(query).split.reject { |word| word.length < 2 }
    return text if words.empty?

    folded = command_fold(text)
    # Une lettre qui se translittère en deux (« œ ») décale les positions :
    # mieux vaut ne rien surligner que surligner à côté.
    return text if folded.length != text.length

    ranges = words.flat_map do |word|
      found = []
      index = folded.index(word)
      while index
        found << (index...(index + word.length))
        index = folded.index(word, index + word.length)
      end
      found
    end
    return text if ranges.empty?

    marks = Array.new(text.length, false)
    ranges.each { |range| range.each { |i| marks[i] = true if i < marks.size } }
    safe_join(text.chars.each_with_index.chunk_while { |(_, a), (_, b)| marks[a] == marks[b] }.map do |chunk|
      part = chunk.map(&:first).join
      marks[chunk.first.last] ? content_tag(:mark, part) : part
    end)
  end

  # Statut d'un séjour en pastille (forme + mot).
  STAY_STATUS_UI = {
    "pending" => [:wait, "En attente"], "pre_confirmed" => [:pre, "Pré-confirmé"], "confirmed" => [:ok, "Confirmé"],
    "canceled" => [:off, "Annulé"], "cancelled" => [:off, "Annulé"], "refused" => [:no, "Refusé"]
  }.freeze

  def command_stay_status(stay)
    kind, label = STAY_STATUS_UI.fetch(stay.status.to_s, [:wait, stay.status.to_s.humanize])
    ui_status(kind, label)
  end

  # « 24 → 27 oct. · La Chevêche »
  def command_stay_line(stay)
    dates = if stay.arrival_date && stay.departure_date && stay.arrival_date != stay.departure_date
              same_month = stay.arrival_date.month == stay.departure_date.month
              "#{l(stay.arrival_date, format: same_month ? '%-d' : '%-d %b')} → #{l(stay.departure_date, format: '%-d %b %Y')}"
            elsif stay.arrival_date
              l(stay.arrival_date, format: "%-d %b %Y")
            end
    lodgings = stay.stay_items.filter_map { |item| item.bookable.try(:lodging)&.name }.uniq
    [dates, *lodgings.first(2)].compact.join(" · ")
  end

  private

  def command_fold(text)
    I18n.transliterate(text.to_s, replacement: "?").downcase
  end
end
