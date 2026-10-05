module Mcp
  module Tools
    module Sejours
      # La fiche client éditable (`CustomersController#update`).
      class ModifierClient < Ecriture
        include Commun

        CHAMPS = {
          "prenom" => :first_name, "nom" => :last_name, "email" => :email, "telephone" => :phone,
          "type" => :customer_type, "organisation" => :organization_name, "tva" => :vat_number, "peppol" => :peppol_id,
          "adresse" => :address_line, "code_postal" => :address_zip, "ville" => :address_city, "pays" => :address_country,
          "langue" => :language, "accepte_nouvelles" => :marketing_consent, "enquete_satisfaction" => :nps_eligible
        }.freeze

        tool "modifier_client",
             title: "Modifier un client",
             description: "Corrige la fiche d'un client : nom, e-mail, téléphone, organisation, TVA, Peppol, adresse, " \
                          "langue, consentements, notes. Aucun email n'est envoyé. Une valeur vide efface le champ.",
             schema: {
               properties: {
                 client: CLIENT,
                 prenom: { type: "string" }, nom: { type: "string" }, email: { type: "string" }, telephone: { type: "string" },
                 type: { type: "string", enum: Customer::CUSTOMER_TYPES }, organisation: { type: "string" },
                 tva: { type: "string" }, peppol: { type: "string" }, adresse: { type: "string" },
                 code_postal: { type: "string" }, ville: { type: "string" }, pays: { type: "string" },
                 langue: { type: "string", enum: Customer::LANGUAGES },
                 accepte_nouvelles: { type: "boolean" }, enquete_satisfaction: { type: "boolean" },
                 notes: { type: "string", description: "Remplace les notes du client." }
               },
               required: %w[client]
             }

        private

        def planifier(arguments)
          client = client!(arguments["client"])
          changements = CHAMPS.filter_map do |cle, champ|
            next unless arguments.key?(cle)

            valeur = arguments[cle].is_a?(String) ? arguments[cle].strip.presence : arguments[cle]
            [champ, valeur] unless client.public_send(champ) == valeur
          end.to_h
          notes = arguments.key?("notes") ? Stays::InternalNote.to_html(arguments["notes"]) : nil
          notes = nil if notes && Stays::InternalNote.plain_text(notes) == client.notes.to_plain_text.strip
          raise Error, "Rien à changer sur la fiche de #{client.name}." if changements.empty? && notes.nil?

          essai = Customer.find(client.id)
          essai.assign_attributes(changements)
          raise Error, "Fiche refusée : #{essai.errors.full_messages.to_sentence}" unless essai.valid?

          libelles = changements.map { |champ, valeur| "#{champ} : #{client.public_send(champ).inspect} → #{valeur.inspect}" }
          libelles << "notes remplacées" if notes
          Plan.new(resume: "#{ligne_client(client)}\n#{libelles.join("\n")}",
                   empreinte: [client.id, client.updated_at.to_f, changements.transform_values(&:to_s), notes],
                   donnees: { client_id: client.id, changements: changements, notes: notes })
        end

        def appliquer(plan)
          client = Customer.find(plan.donnees[:client_id])
          client.assign_attributes(plan.donnees[:changements])
          client.notes = plan.donnees[:notes] if plan.donnees[:notes]
          client.save!
          "Fiche mise à jour : #{ligne_client(client)}."
        end
      end
    end
  end
end
