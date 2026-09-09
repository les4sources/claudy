module RevenueShares
  # Émet un relevé de partage (issue #247).
  #
  # L'émission est le moment où une proposition devient un document : les
  # montants sont figés, l'écriture est passée, le mail est parti. À partir de
  # là, plus rien ne réécrit ce relevé — une réservation qui change de prix
  # après coup revient au relevé suivant en régularisation.
  #
  # Idempotent : ré-émettre un relevé déjà émis ne repasse pas d'écriture et ne
  # renvoie pas le mail. `PostDocument` verrouille la première par son index
  # unique (source, journal) ; le statut verrouille le second.
  class Issue < ServiceBase
    class NoLines < StandardError; end

    def initialize(statement:, whodunnit: nil)
      @statement = statement
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { revenue_share_statement: @statement.id }) { issue }
    end

    def run! = issue

    private

    def issue
      already = false

      PaperTrail.request(whodunnit: @whodunnit || "revenue_share") do
        ApplicationRecord.transaction do
          @statement.lock!

          if @statement.status == "draft"
            raise NoLines, "Ce relevé n'a aucune ligne." if @statement.revenue_share_statement_lines.empty?

            @statement.recompute_totals
            @statement.assign_attributes(status: "issued", issued_at: Time.current)
            @statement.save!
          else
            already = true
          end

          Accounting::PostRevenueShareStatement.new(statement: @statement, whodunnit: @whodunnit).run!
          @statement.update!(posted_at: Time.current) if @statement.posted_at.blank?
        end
      end

      deliver_email unless already
      @statement
    end

    # Le mail part APRÈS la transaction : une livraison qui échoue ne doit pas
    # défaire une émission déjà comptabilisée, et un rollback ne doit pas laisser
    # un mail parti dans la nature. Pas de destinataire ? On ne bloque pas
    # l'émission — l'écran le dit, la page à jeton reste partageable à la main.
    def deliver_email
      return if @statement.revenue_share_agreement.beneficiary_email.blank?

      RevenueShareMailer.statement(@statement).deliver_now
      @statement.update!(sent_at: Time.current)
    end
  end
end
