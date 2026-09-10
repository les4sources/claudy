module Finance
  # Corriger ou retirer une ligne de la feuille de caisse (epic #243, phase 2).
  #
  # Une ligne comptabilisée ne se modifie pas en place : on ANNULE sa passation
  # — ce qui la contre-passe au grand livre, les deux écritures restant lisibles
  # — on corrige, puis on repasse. Une correction qui efface son erreur oblige à
  # croire sur parole.
  #
  # Un mois arrêté (`MonthClosing`) refuse les deux gestes : le mois arrêté est
  # une promesse faite au comptable, pas une suggestion.
  class UpdateCashLine < ServiceBase
    class MonthClosed < StandardError; end

    def initialize(cash_entry:, whodunnit: nil)
      @entry = cash_entry
      @whodunnit = whodunnit
    end

    # `attributes` : motif, entry_date, label, amount_cents, notes.
    def update!(motif:, entry_date:, label:, amount_cents:, notes: nil)
      guard_open_month!
      date = entry_date.is_a?(String) ? Date.parse(entry_date) : entry_date
      guard_open_month!(date)

      PaperTrail.request(whodunnit: @whodunnit || "cash_sheet") do
        ApplicationRecord.transaction do
          unpost!

          cents = motif.signed_cents(amount_cents.to_i)
          raise ArgumentError, "Le montant ne peut pas être nul." if cents.zero?

          @entry.update!(cash_motif: motif, entry_date: date, label: label,
                         notes: notes.presence, amount_cents: cents)
          @entry.cash_allocations.destroy_all
          @entry.cash_allocations.create!(
            motif.allocation_attributes.merge(amount_cents: cents, label: label)
          )
          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run!
        end
      end

      @entry.reload
    end

    # Une ligne ne se détruit jamais (règle B2) : elle s'exclut avec un motif.
    # Une feuille de caisse d'où des lignes disparaissent ne prouve plus rien.
    def exclude!(reason)
      raise ArgumentError, "Un motif est nécessaire pour retirer une ligne." if reason.blank?

      guard_open_month!

      PaperTrail.request(whodunnit: @whodunnit || "cash_sheet") do
        ApplicationRecord.transaction do
          unpost!
          @entry.exclude!(reason)
        end
      end

      @entry.reload
    end

    private

    def unpost!
      return unless @entry.posted?

      Accounting::UnpostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run!
    end

    def guard_open_month!(date = @entry.entry_date)
      return unless MonthClosing.closed?(date)

      raise MonthClosed,
            "#{I18n.l(date.beginning_of_month, format: '%B %Y')} est arrêté — " \
            "cette ligne est en lecture seule."
    end
  end
end
