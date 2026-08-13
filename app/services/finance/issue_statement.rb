module Finance
  # Émet le décompte d'un compte pour un mois (issue #160).
  #
  # L'émission est le moment où des chiffres cessent d'être un affichage pour
  # devenir un document. Quatre gardes la protègent :
  #
  # VERROU PESSIMISTE sur le compte (`with_lock`) : deux émissions simultanées
  # ne peuvent pas lire le même solde et écrire deux décomptes. Le verrou seul
  # ne suffirait pas si les deux processus arrivaient avant l'insertion — c'est
  # l'index unique (compte, mois) qui ferme définitivement la porte.
  #
  # REFUS SI LES RÉCURRENTS MANQUENT. Émettre un décompte incomplet est pire que
  # ne pas l'émettre : le sourcier paie, croit être quitte, et redécouvre sa
  # cagnotte le mois suivant.
  #
  # GEL DES QUATRE MONTANTS, puis verrouillage des écritures couvertes. À partir
  # de là, la seule correction possible est une contre-écriture.
  #
  # VALIDATION DES INVARIANTS SINON ROLLBACK COMPLET : si `clôture = ouverture +
  # débits + crédits` ou `ouverture(N) = clôture(N-1)` ne tient pas, rien n'est
  # écrit et aucune écriture ne reste verrouillée au passage.
  class IssueStatement < ServiceBase
    class RecurringChargesMissing < StandardError; end
    class AlreadyIssued < StandardError; end

    def initialize(member_account:, month:, whodunnit: nil)
      @account = member_account
      @month = month.is_a?(String) ? Date.parse("#{month}-01") : month.to_date.beginning_of_month
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { account: @account.id, month: @month }) { issue }
    end

    def run!
      issue
    end

    private

    def issue
      statement = nil

      PaperTrail.request(whodunnit: @whodunnit || "statement") do
        @account.with_lock do
          raise AlreadyIssued, "Un décompte existe déjà pour #{@month.strftime('%m/%Y')}" if already_issued?
          raise RecurringChargesMissing, missing_charges_message if missing_charges.any?

          statement = build_and_freeze
        end
      end

      statement
    rescue ActiveRecord::RecordNotUnique
      # Deux émissions vraiment concurrentes : l'index a tranché. On renvoie le
      # décompte gagnant plutôt que de lever — le résultat métier est le bon.
      existing_statement
    end

    def already_issued? = existing_statement.present?

    def existing_statement
      AccountStatement.find_by(member_account_id: @account.id, period_month: @month)
    end

    # Les charges récurrentes actives du mois qui n'ont pas encore d'écriture.
    def missing_charges
      @missing_charges ||= RecurringCharge.active_on(@month)
                                          .where(member_account_id: @account.id)
                                          .reject { |charge| charge_generated?(charge) }
    end

    def charge_generated?(charge)
      AccountEntry.unscoped
                  .where("idempotency_key LIKE ?", "recurring:#{charge.id}:#{@month.strftime('%Y-%m')}%")
                  .exists?
    end

    def missing_charges_message
      "Les charges récurrentes du mois ne sont pas générées : " \
        "#{missing_charges.map(&:label).join(', ')}. Génère-les avant d'émettre."
    end

    def build_and_freeze
      entries = coverable_entries.to_a
      previous = AccountStatement.where(member_account_id: @account.id)
                                 .where(period_month: ...@month)
                                 .order(period_month: :desc).first

      opening = previous ? previous.closing_balance_cents : opening_from_history
      debits = entries.select { |e| e.amount_cents.positive? }.sum(&:amount_cents)
      credits = entries.select { |e| e.amount_cents.negative? }.sum(&:amount_cents)

      statement = AccountStatement.create!(
        member_account: @account,
        period_month: @month,
        status: "issued",
        issued_at: Time.current,
        opening_balance_cents: opening,
        debits_cents: debits,
        credits_cents: credits,
        closing_balance_cents: opening + debits + credits
      )

      # `update_all` : les écritures refusent tout `update` une fois verrouillées,
      # et c'est précisément ce verrou qu'on est en train de poser.
      AccountEntry.unscoped.where(id: entries.map(&:id))
                  .update_all(account_statement_id: statement.id, locked_at: Time.current)

      statement
    end

    # Les écritures du mois pas encore rattachées à un décompte.
    def coverable_entries
      AccountEntry.where(member_account_id: @account.id, account_statement_id: nil)
                  .where(entry_date: @month.beginning_of_month..@month.end_of_month)
    end

    # Premier décompte d'un compte : l'ouverture est le solde d'ouverture du
    # compte plus tout ce qui précède le mois émis.
    def opening_from_history
      antérieures = AccountEntry.where(member_account_id: @account.id)
                                .where(entry_date: ...@month.beginning_of_month)
                                .sum(:amount_cents)

      @account.opening_balance_cents + antérieures
    end
  end
end
