module Finance
  # Rattache à la fiche papier d'un mois des écritures posées SANS elle.
  #
  # Cas d'origine : la feuille de bar d'octobre 2026, encodée ligne par ligne
  # par le connecteur (`passer_ecriture`) au lieu de passer par l'écran
  # d'encodage. Les 45 écritures existent, au bon montant, mais aucune fiche ne
  # les porte : la liste des fiches n'en montre rien, et encoder la fiche
  # maintenant REFACTURERAIT tout, puisque `EncodePaperSheet` ne reconnaît que
  # ses propres clés `sheet:<fiche>:<compte>:<article>`.
  #
  # Ce service fait le chemin inverse : il trouve (ou crée) la fiche du mois,
  # retrouve l'article du catalogue de chaque écriture par son libellé, et pose
  # sur l'écriture ce que l'encodage y aurait mis — fiche, article, quantité,
  # clé `sheet:`. Il ne touche JAMAIS au montant, à la date, au compte ni au
  # décompte : les écritures déjà verrouillées par un décompte émis le restent,
  # seules leurs métadonnées de rattachement sont écrites (sans callbacks,
  # puisque le verrou refuse toute mise à jour). Réenregistrer ensuite la
  # fiche à l'écran retrouve ces écritures par leur clé : aucun doublon.
  #
  # Essai à blanc par défaut ; `apply: true` écrit. Rejouable : une écriture
  # déjà rattachée n'est plus candidate.
  class AttachEntriesToPaperSheet
    Line = Struct.new(:entry, :item, :quantity, :unit_price_cents, :reason, keyword_init: true)
    Report = Struct.new(:sheet, :attached, :unmatched, :conflicts, :applied, keyword_init: true) do
      def total_cents = attached.sum { |line| line.entry.amount_cents }
    end

    def initialize(month:, channel: "bar", apply: false, whodunnit: nil)
      @month = month.to_date.beginning_of_month
      @channel = channel.to_s
      @apply = apply
      @whodunnit = whodunnit
      raise ArgumentError, "Canal inconnu : #{@channel}" unless PaperSheet::CHANNELS.include?(@channel)
    end

    def run
      sheet = PaperSheet.find_by(period_month: @month, channel: @channel) ||
              PaperSheet.new(period_month: @month, channel: @channel, entry_mode: "quantity")
      report = Report.new(sheet: sheet, attached: [], unmatched: [], conflicts: [], applied: false)

      classify(report)
      return report unless @apply && report.attached.any?

      write(report)
      report.applied = true
      report
    end

    private

    def candidates
      AccountEntry.where(paper_sheet_id: nil, kind: @channel, flow: @channel,
                         entry_date: @month..@month.end_of_month)
                  .where("amount_cents > 0")
                  .order(:member_account_id, :id)
    end

    def classify(report)
      items = CatalogItem.for_sheet(@channel).includes(:catalog_prices).to_a
      by_name = items.group_by { |item| normalize(item.name) }
      taken = {}

      candidates.each do |entry|
        matches = entry.catalog_item_id ? items.select { |item| item.id == entry.catalog_item_id } : by_name[normalize(entry.label)].to_a
        if matches.size != 1
          reason = matches.empty? ? "aucun article du catalogue à ce nom" : "plusieurs articles à ce nom"
          report.unmatched << Line.new(entry: entry, reason: reason)
          next
        end

        item = matches.first
        cell = [entry.member_account_id, item.id]
        if taken[cell]
          report.conflicts << Line.new(entry: entry, item: item, reason: "même compte et même article que ##{taken[cell].id}")
          next
        end

        taken[cell] = entry
        quantity, unit_price = quantity_for(entry, item)
        report.attached << Line.new(entry: entry, item: item, quantity: quantity, unit_price_cents: unit_price)
      end
    end

    # La quantité n'est posée que si le montant est un multiple exact du prix
    # sourcier du catalogue à la date de la fiche. Sinon (prix changé depuis,
    # prix repris d'une autre fiche), elle reste vide plutôt que d'être fausse.
    def quantity_for(entry, item)
      return [entry.quantity, entry.unit_price_cents] if entry.quantity.present?

      price = item.price_on(@month.end_of_month)&.member_price_cents
      return [nil, nil] if price.nil? || price <= 0 || (entry.amount_cents % price).nonzero?

      [entry.amount_cents / price, price]
    end

    def write(report)
      PaperTrail.request(whodunnit: @whodunnit || "paper_sheet:rattacher") do
        ApplicationRecord.transaction do
          sheet = report.sheet
          all_quantities = report.attached.all?(&:quantity)
          sheet.entry_mode = all_quantities ? "quantity" : "amount"
          sheet.status = "encoded"
          sheet.encoded_at ||= Time.current
          sheet.notes = [sheet.notes.presence, trace(report)].compact.join("\n\n")
          sheet.save!

          report.attached.each do |line|
            key = "sheet:#{sheet.id}:#{line.entry.member_account_id}:#{line.item.id}"
            if AccountEntry.unscoped.where(idempotency_key: key).where.not(id: line.entry.id).exists?
              raise ActiveRecord::RecordNotUnique, "La clé #{key} est déjà prise : rien n'a été écrit."
            end

            # `update_columns` : le verrou du décompte refuse toute mise à jour
            # par callbacks. Montant, date, compte et décompte ne bougent pas.
            line.entry.update_columns(
              paper_sheet_id: sheet.id,
              catalog_item_id: line.item.id,
              quantity: line.quantity,
              unit_price_cents: line.unit_price_cents,
              idempotency_key: key,
              updated_at: Time.current
            )
          end
        end
      end
    end

    def trace(report)
      "#{report.attached.size} écriture(s) déjà au grand livre rattachée(s) le " \
        "#{Date.current.strftime("%d/%m/%Y")} (#{format('%.2f', report.total_cents / 100.0).tr('.', ',')} €), " \
        "sans changer leur montant : ##{report.attached.map { |line| line.entry.id }.minmax.join(' à #')}."
    end

    def normalize(text) = I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
