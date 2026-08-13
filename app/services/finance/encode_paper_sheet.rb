module Finance
  # Enregistre une fiche papier encodée en matrice (issue #158).
  #
  # UNE cellule non vide = UNE écriture. Toutes portent le `paper_sheet_id` de
  # la fiche et un `idempotency_key` de la forme
  # `sheet:<fiche>:<compte>:<article>` : réenregistrer la même fiche MET À JOUR
  # ses écritures au lieu d'en créer un second jeu, et vider une cellule
  # supprime la sienne. C'est ce qui rend l'écran rejouable — on corrige une
  # ligne mal saisie en revenant dessus, pas en créant une contre-écriture.
  #
  # Une écriture déjà VERROUILLÉE (rattachée à un décompte émis, phase 6) n'est
  # ni modifiée ni supprimée : elle est signalée dans le rapport et la cellule
  # reste telle quelle. La correction passera alors par une contre-écriture.
  class EncodePaperSheet < ServiceBase
    Report = Struct.new(:created, :updated, :deleted, :locked, :ignored, keyword_init: true) do
      def touched = created + updated + deleted
      def summary
        "#{created} créée(s), #{updated} mise(s) à jour, #{deleted} supprimée(s)" \
          "#{locked.positive? ? ", #{locked} verrouillée(s) laissée(s) telle(s) quelle(s)" : ''}"
      end
    end

    # `cells` : { member_account_id => { catalog_item_id => valeur saisie } }
    def initialize(sheet:, cells:, entry_mode: nil, whodunnit: nil)
      @sheet = sheet
      @cells = cells || {}
      @entry_mode = entry_mode.presence || sheet.entry_mode
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { sheet: @sheet.id }) { encode }
    end

    def run!
      encode
    end

    private

    def encode
      report = Report.new(created: 0, updated: 0, deleted: 0, locked: 0, ignored: 0)

      PaperTrail.request(whodunnit: @whodunnit || "paper_sheet") do
        ApplicationRecord.transaction do
          @sheet.update!(entry_mode: @entry_mode)
          items = @sheet.catalog_items.index_by(&:id)

          @cells.each do |account_id, per_item|
            per_item.each { |item_id, raw| apply(account_id.to_i, items[item_id.to_i], raw, report) }
          end

          @sheet.update!(status: "encoded", encoded_at: Time.current)
        end
      end

      report
    end

    def apply(account_id, item, raw, report)
      return report.ignored += 1 if item.nil?

      existing = AccountEntry.unscoped.find_by(idempotency_key: key_for(account_id, item.id))
      amount, quantity, unit_price = resolve(item, raw)

      # Cellule vide ou nulle : on supprime l'écriture si elle existait, sinon rien.
      if amount.nil? || amount.zero?
        return if existing.nil?
        return report.locked += 1 if existing.locked?

        existing.destroy!
        return report.deleted += 1
      end

      if existing
        return report.locked += 1 if existing.locked?

        existing.update!(amount_cents: amount, quantity: quantity, unit_price_cents: unit_price,
                         label: item.name, catalog_item_id: item.id)
        report.updated += 1
      else
        AccountEntry.create!(
          member_account_id: account_id,
          entry_date: @sheet.entry_date,
          posted_at: Time.current,
          amount_cents: amount,
          quantity: quantity,
          unit_price_cents: unit_price,
          flow: @sheet.channel,
          kind: @sheet.channel,
          label: item.name,
          catalog_item_id: item.id,
          paper_sheet_id: @sheet.id,
          source: "paper_sheet",
          price_basis: @entry_mode,
          idempotency_key: key_for(account_id, item.id)
        )
        report.created += 1
      end
    end

    # En mode QUANTITÉ la cellule est multipliée par le prix sourcier du moment ;
    # en mode MONTANT elle est prise telle quelle et la quantité reste vide. Les
    # deux modes doivent produire des écritures identiques pour un même total.
    def resolve(item, raw)
      value = parse(raw)
      return [nil, nil, nil] if value.nil?

      if @entry_mode == "quantity"
        price = @sheet.price_for(item)
        return [nil, nil, nil] if price.nil?

        [(value * price.member_price_cents).round, value, price.member_price_cents]
      else
        [(value * 100).round, nil, nil]
      end
    end

    def parse(raw)
      value = raw.to_s.strip.tr(",", ".")
      return nil if value.blank?
      return nil unless value.match?(/\A-?\d+(\.\d+)?\z/)

      value.to_f
    end

    def key_for(account_id, item_id) = "sheet:#{@sheet.id}:#{account_id}:#{item_id}"
  end
end
