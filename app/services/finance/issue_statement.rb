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
  #
  # PAS AVANT LA FIN DU MOIS (2026-11-02). Les décomptes d'octobre 2026 ont été
  # émis le 27 : la feuille de bar et les charges du 31 sont arrivées après, et
  # aucun décompte ne les portait.
  #
  # LES LIGNES ARRIVÉES EN RETARD. Une ligne datée d'un mois déjà couvert (un
  # règlement rapproché après coup porte la date du virement) ne tombe plus
  # dans le vide : le décompte suivant la reprend. Sans ça, la chaîne des
  # décomptes s'écartait du grand livre pour toujours, sans que personne le voie.
  class IssueStatement < ServiceBase
    # Tout refus métier : l'écran et Claude les affichent tels quels.
    class Refused < StandardError; end
    class RecurringChargesMissing < Refused; end
    class AlreadyIssued < Refused; end
    class MonthNotOver < Refused; end

    # Les comptes qui ont eu du bar ces derniers mois mais aucun ce mois-ci :
    # la feuille de bar n'est sans doute pas encore saisie. Un avertissement,
    # pas un refus — un ménage peut ne rien boire pendant un mois.
    BAR_LOOKBACK_MONTHS = 3

    def self.bar_missing?(account, month)
      month = month.to_date.beginning_of_month
      entries = AccountEntry.where(member_account_id: account.id, flow: "bar").where("amount_cents > 0")
      return false if entries.where(entry_date: month..month.end_of_month).exists?

      entries.where(entry_date: (month - BAR_LOOKBACK_MONTHS.months)...month).exists?
    end

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
          raise MonthNotOver, month_not_over_message unless month_over?
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

    def month_over? = Date.current > @month.end_of_month

    def month_not_over_message
      "#{I18n.l(@month, format: '%B %Y').capitalize} n'est pas terminé : le décompte s'émet à partir du " \
        "1er #{I18n.l(@month.next_month, format: '%B')}, une fois la feuille de bar et les charges du mois posées."
    end

    # Les charges récurrentes du mois qui n'ont pas encore d'écriture sur ce
    # compte. La question est posée au générateur lui-même, à blanc, comme le
    # fait l'arrêté du mois : une seule définition de « généré ». Les règles de
    # périmètre (« tous les ménages » : charges, cagnotte, balançoire) y sont,
    # alors que l'ancien contrôle ne voyait que les règles propres au compte —
    # c'est par là que les décomptes d'octobre 2026 sont partis sans les charges.
    def missing_charges
      @missing_charges ||= Finance::GenerateRecurringCharges.new(month: @month, dry_run: true).run!
                                                            .created
                                                            .select { |ligne| ligne[:account].id == @account.id }
                                                            .map { |ligne| ligne[:charge] }
                                                            .uniq
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

    # Les écritures du mois pas encore rattachées à un décompte, plus celles
    # arrivées EN RETARD : datées d'avant le mois, jamais couvertes, et que le
    # premier décompte du compte n'a pas comptées dans son ouverture.
    def coverable_entries
      libres = AccountEntry.where(member_account_id: @account.id, account_statement_id: nil)
      du_mois = libres.where(entry_date: @month.beginning_of_month..@month.end_of_month)

      premier = first_statement
      return du_mois if premier.nil?

      # L'ouverture du premier décompte a compté les lignes datées d'avant son
      # mois QUI EXISTAIENT à son émission. Tout le reste, s'il n'est rattaché
      # à rien, n'est encore sur aucun décompte.
      en_retard = libres.where(entry_date: ...@month.beginning_of_month)
                        .where("account_entries.entry_date >= :debut OR account_entries.created_at > :emis",
                               debut: premier.period_month, emis: premier.issued_at)
      du_mois.or(en_retard)
    end

    def first_statement
      AccountStatement.where(member_account_id: @account.id)
                      .where(period_month: ...@month)
                      .order(:period_month).first
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
