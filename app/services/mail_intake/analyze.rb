module MailIntake
  # Lit un mail rapatrié et prépare la proposition de tri (messagerie, phase 1).
  #
  # Deux étages, dans cet ordre. D'abord le CODE : ce qui se reconnaît à coup
  # sûr (le numéro de TVA d'un fournisseur connu, celui d'une de nos entités,
  # un IBAN déjà en base) ne se demande pas. Ensuite JEV, pour ce que le code
  # ne sait pas trancher : la nature de la pièce, lequel des montants est le
  # total, laquelle des dates est l'échéance. Jev ne choisit que parmi les
  # candidats trouvés dans le texte (`InvoiceCandidates`).
  #
  # Rien ici ne crée de facture : la proposition attend le clic d'un humain.
  # Et si Jev est absent ou muet, le mail entre quand même dans la file, sans
  # proposition — la file ne dépend pas de l'IA.
  class Analyze
    NONE = "aucun".freeze
    MAX_PDF_PAGES = 5
    MAX_TEXT = 8_000
    MAX_SUPPLIER_OPTIONS = 200

    KIND_CRITERIA = {
      "invoice" => "Une facture à payer, émise par un fournisseur à notre nom.",
      "credit_note" => "Une note de crédit : le fournisseur nous rembourse ou annule une facture.",
      "reminder" => "Un rappel de paiement ou une mise en demeure pour une facture déjà reçue.",
      "other" => "Autre chose : conditions générales, devis, bon de commande, publicité, reçu déjà payé."
    }.freeze

    NATURE_CRITERIA = {
      "invoice" => "Le mail apporte ou annonce une facture à payer (en pièce jointe ou par un lien).",
      "reminder" => "Le mail rappelle un paiement en retard.",
      "administrative" => "Courrier administratif ou bancaire : impôts, TVA, banque, assurance, organisme public.",
      "marketing" => "Publicité, newsletter ou prospection.",
      "other" => "Autre chose."
    }.freeze

    def initialize(mail_message:, jev: Jev::Client.new)
      @message = mail_message
      @jev = jev
    end

    def run!
      @message.mail_attachments.each { |attachment| analyze_attachment(attachment) }
      @message.update!(triage: triage, analyzed_at: Time.current)
      @message
    end

    private

    def triage
      return { "error" => "Jev n'est pas configuré" } unless @jev.configured?

      answer = @jev.ask(
        state: { "email" => email_state },
        questions: { "nature" => { type: "choice",
                                   instructions: "Quelle est la nature de ce mail reçu par la comptabilité ?",
                                   criteria: NATURE_CRITERIA } }
      )["nature"]
      { "nature" => { "value" => answer["choice"], "confidence" => answer["confidence"] } }
    rescue Jev::Client::Error => e
      { "error" => e.message }
    end

    def analyze_attachment(attachment)
      return unless attachment.pdf?

      text = attachment.text_content || extract_text(attachment)
      attachment.text_content = text
      candidates = InvoiceCandidates.new(text)
      proposal = code_proposal(candidates)
      proposal.merge!(jev_proposal(attachment, text, candidates, proposal)) if text.present?
      attachment.update!(proposal: proposal)
    end

    def extract_text(attachment)
      reader = PDF::Reader.new(StringIO.new(attachment.file.download))
      reader.pages.first(MAX_PDF_PAGES).map(&:text).join("\n").squeeze(" ").strip
    rescue StandardError => e
      Rails.logger.info("[MailIntake] PDF illisible (pièce ##{attachment.id}) : #{e.class}")
      nil
    end

    # Ce que le code sait sans demander à personne.
    def code_proposal(candidates)
      vats = candidates.vat_numbers
      ibans = candidates.ibans
      proposal = {}

      entity = LegalEntity.actives.find { |e| vats.include?(InvoiceCandidates.normalize_vat(e.vat_number)) }
      proposal["legal_entity_id"] = { "value" => entity.id, "source" => "code" } if entity

      our_vats = LegalEntity.all.filter_map { |e| InvoiceCandidates.normalize_vat(e.vat_number) }
      supplier = suppliers.find do |t|
        vat = InvoiceCandidates.normalize_vat(t.vat_number)
        (vat && vats.include?(vat) && our_vats.exclude?(vat)) ||
          (t.iban.present? && ibans.include?(InvoiceCandidates.normalize_iban(t.iban)))
      end
      supplier ||= suppliers.find { |t| t.email.present? && t.email.casecmp?(@message.from_address.to_s) }
      proposal["third_party_id"] = { "value" => supplier.id, "source" => "code" } if supplier
      proposal
    end

    def jev_proposal(attachment, text, candidates, known)
      return { "error" => "Jev n'est pas configuré" } unless @jev.configured?

      amounts = candidates.amounts
      dates = candidates.dates
      numbers = candidates.numbers
      entities = known.key?("legal_entity_id") ? [] : LegalEntity.actives.ordered.to_a
      supplier_options = known.key?("third_party_id") ? [] : supplier_options_for(text)

      questions = { "kind" => { type: "choice", instructions: "De quel document s'agit-il ?", criteria: KIND_CRITERIA } }
      questions["total"] = pick("Quel est le montant TOTAL à payer de ce document, TVA comprise ?", amounts) if amounts.any?
      if dates.any?
        questions["issued_on"] = pick("Quelle est la date d'émission du document (date de facture) ?", dates)
        questions["due_on"] = pick("Quelle est la date d'échéance, la date limite de paiement ?", dates)
      end
      questions["number"] = pick("Quel est le numéro de cette facture chez le fournisseur ?", numbers) if numbers.any?
      if entities.size > 1
        questions["legal_entity"] = {
          type: "choice", instructions: "À quelle entité cette facture est-elle adressée ?",
          criteria: entities.to_h { |e| [e.name, e.vat_number.present? ? "TVA #{e.vat_number}" : nil] }.merge(NONE => "Aucune de ces entités.")
        }
      end
      if supplier_options.any?
        questions["supplier"] = {
          type: "choice", instructions: "Quel fournisseur a émis ce document ?",
          criteria: supplier_options.to_h { |t| [t.name, nil] }.merge(NONE => "Aucun de ces fournisseurs : c'est un nouveau tiers.")
        }
      end

      answers = @jev.ask(state: { "email" => email_state,
                                  "document" => { "fichier" => attachment.filename, "texte" => text.truncate(MAX_TEXT) } },
                         questions: questions)

      proposal = { "kind" => jev_value(answers["kind"], answers.dig("kind", "choice")) }
      proposal["total_cents"] = picked(answers["total"], amounts)
      proposal["issued_on"] = picked(answers["issued_on"], dates)
      proposal["due_on"] = picked(answers["due_on"], dates)
      proposal["number"] = picked(answers["number"], numbers)
      proposal["legal_entity_id"] = picked_record(answers["legal_entity"], entities)
      proposal["third_party_id"] = picked_record(answers["supplier"], supplier_options)
      proposal.compact
    rescue Jev::Client::Error => e
      { "error" => e.message }
    end

    def pick(instructions, candidates)
      { type: "choice", instructions: instructions,
        criteria: candidates.to_h { |c| [c[:raw], nil] }.merge(NONE => "Aucune de ces valeurs.") }
    end

    def jev_value(answer, value)
      return nil if answer.nil? || value.nil? || value == NONE

      { "value" => value, "source" => "jev", "confidence" => answer["confidence"] }
    end

    # La valeur rendue est celle du candidat, jamais une chaîne venue de Jev.
    def picked(answer, candidates)
      candidate = candidates.find { |c| c[:raw] == answer&.dig("choice") }
      return nil unless candidate

      value = candidate[:value].is_a?(Date) ? candidate[:value].iso8601 : candidate[:value]
      jev_value(answer, value)&.merge("raw" => candidate[:raw])
    end

    def picked_record(answer, records)
      record = records.find { |r| r.name == answer&.dig("choice") }
      record && jev_value(answer, record.id)&.merge("label" => record.name)
    end

    def suppliers
      @suppliers ||= ThirdParty.actives.suppliers.to_a
    end

    # Au-delà de 200 fournisseurs, on ne propose que ceux dont un mot du nom
    # apparaît dans le texte ou l'expéditeur : une liste de mille options
    # n'aide personne à choisir, pas plus Jev qu'un humain.
    def supplier_options_for(text)
      names = suppliers.uniq(&:name)
      return names if names.size <= MAX_SUPPLIER_OPTIONS

      haystack = "#{text} #{@message.from_name} #{@message.from_address}".downcase
      names.select { |t| t.name.downcase.scan(/[[:alnum:]]{4,}/).any? { |word| haystack.include?(word) } }
           .first(MAX_SUPPLIER_OPTIONS)
    end

    def email_state
      { "expediteur" => [@message.from_name, @message.from_address].compact.join(" "),
        "sujet" => @message.subject, "corps" => @message.body_text.to_s.truncate(1_500) }
    end
  end
end
