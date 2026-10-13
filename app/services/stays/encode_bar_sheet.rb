module Stays
  # Encode la feuille de bar d'un groupe sur son séjour (Michael, 2026-10-13).
  #
  # `quantities` : { catalog_item_id => quantité }. Deux modes :
  #   - "set" (l'écran) : la quantité saisie REMPLACE celle du séjour, et une
  #     quantité vide ou nulle retire la ligne. Réenregistrer la feuille la met
  #     à jour, ne la duplique jamais ;
  #   - "add" (une seconde feuille, le connecteur Claude) : la quantité
  #     s'ajoute à celle déjà encodée.
  #
  # Le prix unitaire se fige à la CRÉATION de la ligne (prix public à la date
  # du séjour, cf. `BarConsumption.unit_price_for`) ; changer une quantité ne
  # le relit pas. Un article sans prix à cette date n'est pas encodé : il est
  # signalé, pour qu'on complète le catalogue plutôt que de facturer 0 €.
  #
  # Le total du séjour et son statut de paiement sont recalculés à la fin.
  class EncodeBarSheet < ServiceBase
    MODES = %w[set add].freeze

    Report = Struct.new(:created, :updated, :deleted, :unpriced, :ignored, keyword_init: true) do
      def touched = created + updated + deleted

      def summary
        parts = []
        parts << "#{created} ajoutée#{'s' if created > 1}" if created.positive?
        parts << "#{updated} modifiée#{'s' if updated > 1}" if updated.positive?
        parts << "#{deleted} retirée#{'s' if deleted > 1}" if deleted.positive?
        parts.any? ? "Lignes du bar : #{parts.join(', ')}." : "Aucune ligne du bar modifiée."
      end
    end

    attr_reader :stay, :report

    def initialize(stay:, quantities:, mode: "set")
      @stay = stay
      @quantities = (quantities || {}).to_h
      @mode = MODES.include?(mode.to_s) ? mode.to_s : "set"
    end

    def run
      catch_error(context: { stay_id: stay.id }) { run! }
    end

    def run!
      @report = Report.new(created: 0, updated: 0, deleted: 0, unpriced: [], ignored: 0)

      ApplicationRecord.transaction do
        items = BarConsumption.catalog_items.where(id: @quantities.keys.map(&:to_i)).index_by(&:id)
        lines = stay.bar_consumptions.index_by(&:catalog_item_id)

        @quantities.each do |item_id, raw|
          item = items[item_id.to_i]
          next @report.ignored += 1 if item.nil?

          apply(item, lines[item.id], quantity_from(raw))
        end

        stay.recompute_aggregates!
        stay.set_payment_status
      end

      @report
    end

    private

    # « 3 », « 3,0 », « » : la saisie est libre, la quantité est un entier. Une
    # valeur illisible vaut une case vide plutôt qu'une erreur au milieu de la
    # feuille.
    def quantity_from(raw)
      value = raw.to_s.strip.tr(",", ".")
      return 0 if value.empty?

      Float(value).round
    rescue ArgumentError
      0
    end

    def apply(item, line, quantity)
      target = @mode == "add" ? line&.quantity.to_i + quantity : quantity

      if target <= 0
        return if line.nil?

        line.soft_delete!
        @report.deleted += 1
      elsif line
        return if line.quantity == target

        line.update!(quantity: target)
        @report.updated += 1
      else
        unit_price = BarConsumption.unit_price_for(item, on: BarConsumption.price_date_for(stay))
        return @report.unpriced << item.name if unit_price.nil?

        stay.bar_consumptions.create!(catalog_item: item, label: item.name, quantity: target, unit_price_cents: unit_price)
        @report.created += 1
      end
    end
  end
end
