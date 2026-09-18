module Accounting
  # Comptabilise le règlement d'un événement (epic #245, décision 6).
  #
  # Débit du compte « rémunérations d'intervenants » — avec le PÔLE de
  # l'événement, c'est là que se joue la lecture par pôle — crédit du `440000`,
  # UNE LIGNE PAR ORGANISATEUR avec son tiers. Le tiers est sur la ligne et non
  # sur l'écriture : c'est cette ligne 440000 qu'on lettrera contre son virement.
  #
  # Idempotent : `PostDocument` rend l'écriture existante si le même règlement a
  # déjà été passé dans le même journal.
  class PostEventSettlement < ServiceBase
    class MissingAccount < StandardError; end
    class NothingToPost < StandardError; end

    SUPPLIER_CODE = "440000".freeze
    FEE_CODE = GeneralAccount::CONTRIBUTOR_FEE_CODE

    def initialize(event_settlement:, whodunnit: nil)
      @settlement = event_settlement
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { event_settlement: @settlement&.id }) { post }
    def run! = post

    private

    def post
      lines = @settlement.event_settlement_lines.includes(:human).to_a
      raise NothingToPost, "Ce règlement n'a aucune part à payer." if lines.empty?

      entry = PostDocument.new(
        legal_entity: legal_entity,
        journal: "purchases",
        entry_date: (@settlement.issued_at || Time.current).to_date,
        label: @settlement.label,
        source: @settlement,
        whodunnit: @whodunnit,
        lines: [fee_line] + supplier_lines(lines)
      ).run!

      @settlement.update_column(:posted_at, Time.current) if @settlement.posted_at.blank?
      entry
    end

    # UNE seule ligne de charge, portée par le pôle de l'événement : la lecture
    # analytique se fait par pôle, pas par organisateur.
    def fee_line
      {
        account: fee_account,
        team: @settlement.event.team,
        label: @settlement.label,
        debit_cents: @settlement.organizers_cents
      }
    end

    def supplier_lines(lines)
      lines.map do |line|
        {
          account: supplier_account,
          third_party: ThirdParty.for_human!(line.human),
          label: line.human.name,
          credit_cents: line.amount_cents
        }
      end
    end

    def fee_account
      GeneralAccount.find_by(code: FEE_CODE) ||
        raise(MissingAccount,
              "Le compte #{FEE_CODE} n'existe pas — lance `rake accounting:seed_reference`.")
    end

    def supplier_account
      GeneralAccount.find_by(code: SUPPLIER_CODE) ||
        raise(MissingAccount,
              "Le compte fournisseurs #{SUPPLIER_CODE} n'existe pas — lance `rake accounting:seed_reference`.")
    end

    def legal_entity
      @settlement.event.try(:legal_entity) || LegalEntity.actives.ordered.first
    end
  end
end
