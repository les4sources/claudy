module Finance
  # Le fichier de virements SEPA d'une structure (Michael, 2026-11-05) : on
  # coche des dettes de la file « À payer », Claudy écrit le fichier
  # pain.001.001.03 que Triodos Internet Banking importe (Opérations ›
  # Importation), et il ne reste qu'à autoriser le lot dans la banque.
  #
  # UN FICHIER = UNE STRUCTURE = UN COMPTE DÉBITEUR. La Fondation et la SRL
  # n'ont ni le même compte ni les mêmes signataires ; mélanger leurs dettes
  # dans un lot ferait payer l'une par l'autre.
  #
  # LE FICHIER NE PAIE RIEN. Générer n'est pas virer : le lot peut ne jamais
  # être autorisé, ou l'être à moitié. Les dettes restent donc « à payer » ; elles
  # se soldent comme avant, quand le relevé bancaire ramène chaque virement et
  # qu'on le rapproche (décision 4 du contrat `Payable` : le paiement est un
  # rapprochement, jamais une case à cocher). D'où `BtchBookg = false` : un
  # virement par ligne sur l'extrait, donc une ligne de trésorerie par dette,
  # que le rapprochement retrouve — un lot groupé arriverait en une seule
  # ligne, impossible à répartir.
  #
  # Format : ISO 20022 pain.001.001.03, guide Febelfin pour les banques belges.
  # Pas de BIC du bénéficiaire (« IBAN only », permis dans l'Espace économique
  # européen depuis 2016) : Claudy n'en stocke pas, et un IBAN hors EEE — Suisse,
  # Royaume-Uni… — exige un BIC, il est donc refusé ici et se vire à la main.
  class SepaCreditTransfer
    NAMESPACE = "urn:iso:std:iso:20022:tech:xsd:pain.001.001.03".freeze

    # Les pays de l'EEE (et ceux qui partagent l'IBAN français), où un virement
    # SEPA part sur le seul IBAN.
    IBAN_ONLY_COUNTRIES = %w[
      AT BE BG CY CZ DE DK EE ES FI FR GR HR HU IE IS IT LI LT LU LV MT NL NO PL PT RO SE SI SK
    ].freeze

    # Le BIC de la banque débitrice, d'après le code banque d'un IBAN belge
    # (positions 5 à 7, registre de la BNB). Febelfin le demande ; une banque
    # inconnue d'ici reçoit « NOTPROVIDED », que le schéma admet.
    BELGIAN_BICS = {
      "523" => "TRIOBEBB", # Triodos
      **(950..959).to_h { |code| [code.to_s, "CTBKBEBX"] } # Beobank
    }.freeze

    # Le jeu de caractères SEPA (EPC, « Latin de base ») : le reste — accents
    # compris — est translittéré ou retiré, sinon la banque refuse le fichier.
    UNSAFE_CHARACTERS = %r{[^A-Za-z0-9/\-?:().,'+ ]}

    Transfer = Data.define(:payable, :amount_cents, :name, :iban, :end_to_end_id, :structured_reference, :remittance)

    class Error < StandardError; end

    # Ce qui empêche une dette de partir dans un fichier, en une phrase, ou nil.
    # L'écran l'affiche à la place de la case à cocher : une dette qu'on ne peut
    # pas virer reste visible, avec sa raison.
    def self.problem_for(payable)
      return "Note de crédit : c'est le fournisseur qui te rembourse." if payable.try(:credit_note?)
      return "Rien à virer : déjà couvert par les rapprochements." unless payable.remaining_cents.positive?
      # Domiciliée (2026-11-12) : la banque la prélève, la virer la paierait deux fois.
      return "Réglée par compensation : rien à virer." if payable.try(:settled_by_offset?)
      if payable.try(:direct_debit?)
        return "Domiciliation : la banque la prélève#{" le #{I18n.l(payable.settled_on, format: :short)}" if payable.settled_on}, pas de virement."
      end
      return "Bénéficiaire sans nom." if payable.payable_beneficiary.blank?

      iban = normalize_iban(payable.payable_iban)
      return "Pas d'IBAN : ajoute-le sur la fiche du bénéficiaire." if iban.blank?
      return "IBAN invalide (#{iban}) : corrige-le sur la fiche du bénéficiaire." unless IbanValidator.valid_iban?(iban)
      return "IBAN hors Espace économique européen : ce virement demande un BIC, fais-le à la main." unless IBAN_ONLY_COUNTRIES.include?(iban[0, 2])

      nil
    end

    def self.normalize_iban(value) = value.to_s.gsub(/[^A-Za-z0-9]/, "").upcase.presence

    # Les comptes bancaires d'où la structure peut virer : ceux qui portent un
    # IBAN valide. Le compte à vue d'abord (le plus petit code 55), l'épargne
    # ensuite.
    def self.debtor_accounts(legal_entity)
      CashAccount.actives.where(kind: "bank", legal_entity: legal_entity).includes(:general_account).to_a
                 .select { |account| IbanValidator.valid_iban?(normalize_iban(account.iban).to_s) }
                 .sort_by { |account| [account.general_account&.code.to_s, account.name] }
    end

    def self.clean(text, limit)
      ActiveSupport::Inflector.transliterate(text.to_s).gsub(UNSAFE_CHARACTERS, " ").squeeze(" ").strip.first(limit).strip
    end

    attr_reader :legal_entity, :debtor_account, :execution_date, :transfers

    def initialize(legal_entity:, debtor_account:, payables:, execution_date: Date.current, created_at: Time.current)
      @legal_entity = legal_entity
      @debtor_account = debtor_account
      @execution_date = execution_date
      @created_at = created_at
      @payables = payables
      check!
      @transfers = payables.map { |payable| transfer_for(payable) }
    end

    def total_cents = transfers.sum(&:amount_cents)

    def filename
      "virements-#{legal_entity.name.parameterize}-#{execution_date.iso8601}.xml"
    end

    def message_id
      @message_id ||= "CLAUDY-#{@created_at.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3).upcase}"
    end

    def to_xml
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.Document(xmlns: NAMESPACE) do
          xml.CstmrCdtTrfInitn do
            group_header(xml)
            payment_information(xml)
          end
        end
      end.to_xml
    end

    private

    def check!
      raise Error, "Coche au moins un virement." if @payables.empty?
      raise Error, "La date d'exécution ne peut pas être passée." if execution_date < Date.current
      raise Error, "#{legal_entity.name} n'a pas de compte bancaire avec un IBAN valide." unless debtor_account
      raise Error, "Ce compte n'appartient pas à #{legal_entity.name}." unless debtor_account.legal_entity_id == legal_entity.id

      @payables.each do |payable|
        if payable.payable_legal_entity != legal_entity
          raise Error, "#{payable.payable_beneficiary} est une dette d'une autre structure : un fichier par structure."
        end
        problem = self.class.problem_for(payable)
        raise Error, "#{payable.payable_beneficiary} : #{problem}" if problem
      end
    end

    def transfer_for(payable)
      communication = (payable.payable_communication.presence || payable.payable_reference).to_s
      structured = MailIntake::StructuredCommunication.normalize(communication)&.gsub(/\D/, "")
      Transfer.new(
        payable: payable,
        amount_cents: payable.remaining_cents,
        name: self.class.clean(payable.payable_beneficiary, 70),
        iban: self.class.normalize_iban(payable.payable_iban),
        end_to_end_id: end_to_end_id(payable),
        structured_reference: structured,
        remittance: structured ? nil : self.class.clean(communication, 140).presence || payable_label(payable)
      )
    end

    # Unique et lisible au retour : « PI-123 » pour la facture d'achat #123.
    def end_to_end_id(payable)
      prefix = payable.class.name.demodulize.scan(/[A-Z]/).join
      self.class.clean("#{prefix}-#{payable.id}", 35).tr(" ", "-")
    end

    def payable_label(payable) = self.class.clean(payable.payable_label, 140)

    def amount(cents) = format("%.2f", cents / 100.0)

    def debtor_iban = self.class.normalize_iban(debtor_account.iban)

    def debtor_bic
      BELGIAN_BICS[debtor_iban[4, 3]] if debtor_iban.start_with?("BE")
    end

    def group_header(xml)
      xml.GrpHdr do
        xml.MsgId message_id
        xml.CreDtTm @created_at.strftime("%Y-%m-%dT%H:%M:%S")
        xml.NbOfTxs transfers.size
        xml.CtrlSum amount(total_cents)
        xml.InitgPty { xml.Nm self.class.clean(legal_entity.name, 70) }
      end
    end

    def payment_information(xml)
      xml.PmtInf do
        xml.PmtInfId "#{message_id}-1"
        xml.PmtMtd "TRF"
        xml.BtchBookg false
        xml.NbOfTxs transfers.size
        xml.CtrlSum amount(total_cents)
        xml.PmtTpInf { xml.SvcLvl { xml.Cd "SEPA" } }
        xml.ReqdExctnDt execution_date.iso8601
        xml.Dbtr { xml.Nm self.class.clean(legal_entity.name, 70) }
        xml.DbtrAcct do
          xml.Id { xml.IBAN debtor_iban }
          xml.Ccy "EUR"
        end
        xml.DbtrAgt do
          xml.FinInstnId do
            if debtor_bic
              xml.BIC debtor_bic
            else
              xml.Othr { xml.Id "NOTPROVIDED" }
            end
          end
        end
        xml.ChrgBr "SLEV"
        transfers.each { |transfer| credit_transfer(xml, transfer) }
      end
    end

    def credit_transfer(xml, transfer)
      xml.CdtTrfTxInf do
        xml.PmtId { xml.EndToEndId transfer.end_to_end_id }
        xml.Amt { xml.InstdAmt(amount(transfer.amount_cents), Ccy: "EUR") }
        xml.Cdtr { xml.Nm transfer.name }
        xml.CdtrAcct { xml.Id { xml.IBAN transfer.iban } }
        xml.RmtInf do
          if transfer.structured_reference
            # La communication structurée belge (+++…+++) : le fournisseur la
            # rapproche automatiquement, elle part donc structurée, pas en texte.
            xml.Strd do
              xml.CdtrRefInf do
                xml.Tp do
                  xml.CdOrPrtry { xml.Cd "SCOR" }
                  xml.Issr "BBA"
                end
                xml.Ref transfer.structured_reference
              end
            end
          else
            xml.Ustrd transfer.remittance
          end
        end
      end
    end
  end
end
