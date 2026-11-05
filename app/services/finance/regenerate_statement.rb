module Finance
  # Régénérer (ou annuler) un décompte émis trop tôt (2026-11-02).
  #
  # Les décomptes d'octobre 2026 ont été émis avant la feuille de bar et les
  # charges du 31 : leurs soldes figés ne disaient plus rien du grand livre, et
  # aucun geste ne permettait de les reprendre.
  #
  # Le geste n'existe que pour un décompte que PERSONNE N'A LU : émis, jamais
  # envoyé ni relancé, pas réglé, et le dernier du compte (ceux d'après
  # s'ouvrent sur sa clôture). Une fois parti, un décompte reste ce qu'il est ;
  # la correction passe par le décompte suivant.
  #
  # Tout ou rien, dans une transaction : les lignes couvertes sont déverrouillées,
  # le décompte part à la corbeille (PaperTrail garde sa trace et ses montants),
  # puis, pour une régénération, le décompte du mois est réémis avec les mêmes
  # gardes qu'une émission normale. Si la réémission est refusée (une charge du
  # mois manque, par exemple), rien n'a bougé.
  class RegenerateStatement < ServiceBase
    class Refused < Finance::IssueStatement::Refused; end

    Result = Struct.new(:previous, :statement, keyword_init: true)

    def initialize(statement:, whodunnit: nil, reissue: true)
      @statement = statement
      @whodunnit = whodunnit
      @reissue = reissue
    end

    def run!
      regenerate
    end

    private

    def regenerate
      result = nil
      account = @statement.member_account

      PaperTrail.request(whodunnit: @whodunnit || "statement") do
        AccountStatement.transaction do
          account.lock!
          @statement.lock!
          refusal = @statement.regeneration_refusal
          raise Refused, "Le décompte ##{@statement.id} ne peut pas être #{verbe} : #{refusal}." if refusal

          before = snapshot(@statement)

          # `update_all` : une ligne verrouillée refuse tout `update`, et c'est
          # précisément ce verrou qu'on lève ici.
          AccountEntry.unscoped.where(account_statement_id: @statement.id)
                      .update_all(account_statement_id: nil, locked_at: nil, updated_at: Time.current)
          @statement.soft_delete!(validate: false)

          statement = if @reissue
                        Finance::IssueStatement.new(member_account: account, month: @statement.period_month,
                                                    whodunnit: @whodunnit).run!
                      end
          result = Result.new(previous: before, statement: statement)
        end
      end

      result
    end

    def verbe = @reissue ? "régénéré" : "annulé"

    def snapshot(statement)
      statement.attributes.slice("id", "opening_balance_cents", "debits_cents", "credits_cents", "closing_balance_cents")
               .symbolize_keys
    end
  end
end
