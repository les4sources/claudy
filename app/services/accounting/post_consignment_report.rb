module Accounting
  # L'écriture d'un relevé de dépôt-vente réglé par virement (epic #248, phase 3).
  #
  # Ce que la maison achète à l'artisan, c'est sa part : le NET. La commission
  # n'est pas une charge — elle est déjà dans le chiffre d'affaires de l'épicerie,
  # entré par la caisse et Stripe (décision 6). Passer le brut en charge puis la
  # commission en produit gonflerait les deux côtés du compte de résultat sans
  # rien apprendre à personne.
  #
  # D'où une écriture à deux lignes : débit « achats de marchandises », crédit
  # `440000` avec le tiers de l'artisan — la ligne qu'on lettrera contre le
  # virement.
  #
  # Un artisan payé en VOLONTARIAT (Michael, 2026-10-22) ne nous vend rien : son
  # net est un défraiement de volontaire. La charge va alors en `619105` et
  # l'écriture sur la Fondation, qui porte le volontariat.
  #
  # Idempotent par construction : `PostDocument` rend l'écriture existante quand
  # le même document repasse dans le même journal.
  class PostConsignmentReport < ServiceBase
    class MissingAccount < StandardError; end
    class MissingEntity < StandardError; end
    class NothingToPost < StandardError; end

    SUPPLIER_CODE  = "440000".freeze
    GOODS_CODE     = "600000".freeze
    VOLUNTEERING_CODE = "619105".freeze

    # Le compte de charge que le mode de règlement de l'artisan appelle.
    def self.charge_code_for(report)
      report.consignor&.volunteering? ? VOLUNTEERING_CODE : GOODS_CODE
    end

    # L'entité qui porte la dette : la Fondation pour un volontaire, sinon la
    # première entité active, comme depuis le début du dépôt-vente.
    def self.entity_for(report)
      if report.consignor&.volunteering?
        LegalEntity.actives.find_by(form: "foundation")
      else
        LegalEntity.actives.ordered.first
      end
    end

    def initialize(consignment_report:, whodunnit: nil)
      @report = consignment_report
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { consignment_report: @report&.id }) { post }
    def run! = post

    private

    def post
      net = @report.net_cents.to_i
      raise NothingToPost, "Ce relevé ne doit rien à l'artisan." unless net.positive?

      entity = self.class.entity_for(@report)
      if entity.blank?
        raise MissingEntity,
              @report.consignor&.volunteering? ? "Aucune Fondation active — le volontariat ne se comptabilise pas." :
                                                 "Aucune entité juridique active — impossible de comptabiliser."
      end

      PostDocument.new(
        legal_entity: entity,
        journal: "purchases",
        entry_date: @report.verified_at&.to_date || Date.current,
        label: label,
        source: @report,
        whodunnit: @whodunnit,
        lines: [
          { account: charge_account, label: label, debit_cents: net },
          { account: supplier_account, third_party: third_party, label: label, credit_cents: net }
        ]
      ).run!
    end

    def label = "Dépôt-vente #{@report.period_label} — #{@report.consignor&.name}"

    # Le tiers de l'artisan : celui déjà lié au contrat s'il existe, sinon celui
    # du membre du collectif, sinon un tiers dédié créé à son nom. Un artisan
    # qui n'est pas un `Human` n'a pas à le devenir pour être payé.
    def third_party
      return @report.consignor.third_party if @report.consignor.third_party
      return ThirdParty.for_human!(@report.consignor.human) if @report.consignor.human

      ThirdParty.find_or_create_by!(name: @report.consignor.name) do |tp|
        tp.kind = "supplier"
        tp.email = @report.consignor.email.presence
      end
    end

    def charge_account
      code = self.class.charge_code_for(@report)
      GeneralAccount.find_by(code: code) ||
        raise(MissingAccount,
              "Le compte #{code} n'existe pas — lance `rake accounting:seed_reference`.")
    end

    def supplier_account
      GeneralAccount.find_by(code: SUPPLIER_CODE) ||
        raise(MissingAccount,
              "Le compte #{SUPPLIER_CODE} n'existe pas — lance `rake accounting:seed_reference`.")
    end
  end
end
