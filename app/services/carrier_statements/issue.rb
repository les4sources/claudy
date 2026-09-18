module CarrierStatements
  # Émet un relevé de porteur (epic #244, phase 3).
  #
  # L'émission est le moment où une proposition devient un document : le total
  # est figé, l'écriture est passée, le mail est parti. À partir de là, plus rien
  # ne réécrit ce relevé — une erreur se corrige par contre-passation, et une
  # prestation oubliée revient au relevé suivant.
  #
  # Idempotent : ré-émettre un relevé déjà émis ne repasse pas d'écriture et ne
  # renvoie pas le mail. `PostDocument` verrouille la première par son index
  # unique (source, journal) ; le statut verrouille le second.
  class Issue < ServiceBase
    class NoLines < StandardError; end

    attr_reader :statement

    def initialize(statement:, whodunnit: nil)
      @statement = statement
      @whodunnit = whodunnit
      @report_errors = false
    end

    def run = catch_error(context: { carrier_statement: @statement.id }) { issue }
    def run! = issue

    private

    def issue
      already = false

      PaperTrail.request(whodunnit: @whodunnit || "carrier_statement") do
        ApplicationRecord.transaction do
          @statement.lock!

          if @statement.draft?
            raise NoLines, "Ce relevé n'a aucune ligne." if @statement.carrier_statement_lines.empty?

            @statement.recompute_total
            @statement.assign_attributes(status: "issued", issued_at: Time.current)
            @statement.save!
          else
            already = true
          end

          Accounting::PostCarrierStatement.new(statement: @statement, whodunnit: @whodunnit).run!
          @statement.update!(posted_at: Time.current) if @statement.posted_at.blank?
        end
      end

      deliver_email unless already
      @statement
    end

    # Le mail part APRÈS la transaction : une livraison qui échoue ne doit pas
    # défaire une émission déjà comptabilisée, et un rollback ne doit pas laisser
    # un mail parti dans la nature. Pas d'adresse ? On ne bloque pas l'émission —
    # l'écran le dit, la page à jeton reste partageable à la main.
    def deliver_email
      return if @statement.human.email.blank?

      CarrierStatementMailer.statement(@statement).deliver_now
      @statement.update!(sent_at: Time.current)
    end
  end
end
