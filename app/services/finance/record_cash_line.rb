module Finance
  # Une ligne de la feuille de caisse (epic #243, phase 2).
  #
  # Trois gestes, pas six écrans : un motif, un montant, un libellé. Le motif EST
  # l'affectation (décision 2) — il porte le compte général, le pôle, l'entité et
  # le sens — donc la ligne naît affectée et comptabilisée dans la foulée. C'est
  # toute la différence avec `/finance/cash_entries/new`, qui demande un second
  # geste d'affectation : pour trente lignes de feuille mensuelle, ce second
  # geste est ce qui fait qu'on ne saisit pas.
  #
  # L'allocation est une COPIE des attributs du motif, jamais une référence : un
  # motif réaffecté l'an prochain ne doit pas réécrire la caisse de cette année.
  class RecordCashLine < ServiceBase
    class MonthClosed < StandardError; end
    class MissingMotif < StandardError; end

    def initialize(cash_account:, motif:, entry_date:, label:, amount_cents:, notes: nil, whodunnit: nil)
      @account = cash_account
      @motif = motif
      @entry_date = entry_date.is_a?(String) ? Date.parse(entry_date) : entry_date
      @label = label
      @amount_cents = amount_cents.to_i
      @notes = notes.presence
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { cash_account: @account&.id }) { record }
    end

    def run! = record

    private

    def record
      raise MissingMotif, "Choisis un motif — c'est lui qui affecte la ligne." if @motif.blank?
      if MonthClosing.closed?(@entry_date)
        raise MonthClosed,
              "#{I18n.l(@entry_date.beginning_of_month, format: '%B %Y')} est arrêté — " \
              "une correction s'y fait par écriture, pas en saisissant une ligne."
      end

      entry = nil

      PaperTrail.request(whodunnit: @whodunnit || "cash_sheet") do
        ApplicationRecord.transaction do
          entry = CashEntry.create!(
            cash_account: @account, cash_motif: @motif, entry_date: @entry_date,
            label: @label, notes: @notes, amount_cents: signed_cents
          )
          entry.cash_allocations.create!(
            @motif.allocation_attributes.merge(amount_cents: signed_cents, label: @label)
          )
          Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run!
        end
      end

      entry.reload
    end

    # Le sens vient du MOTIF, pas d'un signe que la personne devrait taper : au
    # bar, sur un téléphone, « −25 » se saisit une fois sur deux en « 25 ».
    def signed_cents
      cents = @motif.signed_cents(@amount_cents)
      raise ArgumentError, "Le montant ne peut pas être nul." if cents.zero?

      cents
    end
  end
end
