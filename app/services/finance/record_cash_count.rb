module Finance
  # Le comptage de la caisse (epic #243, phase 3).
  #
  # Le service fige l'écart (décision 3) et, quand on l'assume, écrit l'écriture
  # d'ajustement. C'est le seul endroit qui sait faire les deux, et c'est
  # volontaire : un comptage validé sans son écriture, ou une écriture sans son
  # comptage, seraient deux moitiés de vérité.
  #
  # Deux issues à un écart, jamais une troisième :
  #
  # - `investigate` — on va retrouver l'origine. Le comptage reste BROUILLON, le
  #   solde théorique n'est pas figé, et l'écran renvoie à la feuille pour
  #   saisir la ligne manquante. Rien n'est écrit en comptabilité.
  # - `unexplained` — on assume. Le comptage est validé, l'écart figé, une ligne
  #   de caisse d'ajustement est saisie sur « Écarts de caisse » et
  #   comptabilisée dans la foulée.
  #
  # Une caisse qui tombe juste n'a besoin ni de commentaire ni d'issue.
  class RecordCashCount < ServiceBase
    class MissingAccount < StandardError; end
    class MissingDifferenceAccount < StandardError; end
    class AlreadyValidated < StandardError; end
    class MissingResolution < StandardError; end

    ADJUSTMENT_MOTIF_LABEL = "Écart de caisse".freeze

    def initialize(cash_account:, counted_on:, denominations:, comment: nil, resolution: nil,
                   counted_by: nil, count: nil, whodunnit: nil)
      @account = cash_account
      @counted_on = counted_on.is_a?(String) ? Date.parse(counted_on) : counted_on
      @denominations = normalize(denominations)
      @comment = comment.presence
      @resolution = resolution.presence
      @counted_by = counted_by
      @count = count
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { cash_account: @account&.id }) { record }
    def run! = record

    private

    def record
      raise MissingAccount, "Aucune caisse active — la feuille de caisse en désigne une." if @account.blank?
      raise AlreadyValidated, "Ce comptage est déjà validé." if @count&.validated?

      counted = CashCount.total_cents(@denominations)
      expected = Finance::CashSheet.accounting_balance(cash_account: @account, up_to: @counted_on)
      difference = counted - expected

      if difference.nonzero? && @resolution.blank?
        raise MissingResolution,
              "La caisse ne tombe pas juste : dis si tu vas retrouver l'origine, ou si l'écart est inexpliqué."
      end

      count = @count || CashCount.new(cash_account: @account)

      PaperTrail.request(whodunnit: @whodunnit || "cash_count") do
        ApplicationRecord.transaction do
          count.assign_attributes(
            counted_on: @counted_on, denominations: @denominations, counted_cents: counted,
            expected_cents: expected, difference_cents: difference, comment: @comment,
            resolution: difference.zero? ? nil : @resolution, counted_by: @counted_by || count.counted_by
          )

          if difference.nonzero? && @resolution == "investigate"
            count.status = "draft"
            count.validated_at = nil
            count.save!
          else
            count.status = "validated"
            count.validated_at = Time.current
            # L'ajustement se crée AVANT la validation : `validated_count_is_immutable`
            # verrouille le comptage dès qu'il est validé, y compris pour y
            # accrocher son écriture.
            count.adjustment_cash_entry = adjustment_entry(difference) if difference.nonzero?
            count.save!
          end
        end
      end

      count.reload
    end

    # L'ajustement passe par la feuille de caisse, comme n'importe quelle ligne :
    # même service, même motif, même passation. Une écriture fabriquée
    # directement contournerait les règles du mois arrêté — et l'ajustement
    # d'un mois arrêté est précisément ce qu'on ne veut pas laisser passer.
    def adjustment_entry(difference)
      Finance::RecordCashLine.new(
        cash_account: @account,
        motif: adjustment_motif,
        entry_date: @counted_on,
        label: "Écart de caisse du #{I18n.l(@counted_on, format: :short)}",
        amount_cents: difference,
        notes: @comment,
        whodunnit: @whodunnit
      ).run!
    end

    # Le motif d'ajustement est créé à la demande, pas semé : il n'a rien à faire
    # dans la liste que la personne au bar déroule — il ne se choisit jamais à la
    # main. `both` parce que l'écart va dans les deux sens.
    def adjustment_motif
      CashMotif.unscoped.find_by(label: ADJUSTMENT_MOTIF_LABEL) ||
        CashMotif.create!(
          label: ADJUSTMENT_MOTIF_LABEL, direction: "both", general_account: difference_account,
          legal_entity: @account.legal_entity, active: false, position: CashMotif.next_position
        )
    end

    def difference_account
      GeneralAccount.find_by(code: GeneralAccount::CASH_DIFFERENCE_CODE) ||
        raise(MissingDifferenceAccount,
              "Le compte « Écarts de caisse » #{GeneralAccount::CASH_DIFFERENCE_CODE} n'existe pas — " \
              "lance `rake accounting:seed_reference`.")
    end

    # La grille telle qu'elle a été tapée, nettoyée : clés en euros à deux
    # décimales, quantités entières, zéros retirés.
    def normalize(raw)
      (raw || {}).each_with_object({}) do |(unit, quantity), grille|
        unit_cents = unit.is_a?(Integer) ? unit : (unit.to_s.tr(",", ".").to_f * 100).round
        next unless CashCount::DENOMINATIONS.include?(unit_cents)

        count = quantity.to_i
        next unless count.positive?

        grille[CashCount.denomination_key(unit_cents)] = count
      end
    end
  end
end
