module Mcp
  module Tools
    module Sejours
      # Ce que partagent les outils des séjours : retrouver un séjour ou un
      # client, et les décrire en une ligne lisible, identifiants compris.
      module Commun
        SEJOUR = {
          type: %w[integer string],
          description: "Identifiant du séjour (« 1234 » ou « #1234 »), rendu par chercher_sejours."
        }.freeze

        CLIENT = {
          type: %w[integer string],
          description: "Client : identifiant (#87), adresse e-mail, ou nom. Plusieurs candidats : l'outil les liste."
        }.freeze

        STATUTS = {
          "pending" => "en attente", "pre_confirmed" => "pré-confirmé", "confirmed" => "confirmé",
          "canceled" => "annulé", "cancelled" => "annulé"
        }.freeze

        PAIEMENT_SEJOUR = { "pending" => "rien payé", "partially_paid" => "payé en partie", "paid" => "soldé" }.freeze

        METHODES = {
          "cash" => "espèces", "bank_transfer" => "virement", "card" => "carte", "stripe" => "en ligne (Stripe)",
          "airbnb" => "Airbnb", "bookingdotcom" => "Booking.com", "tranchesdevie" => "Tranches de Vie"
        }.freeze

        STATUTS_PAIEMENT = { "pending" => "en attente", "paid" => "payé", "refunded" => "remboursé" }.freeze

        private

        def sejour!(reference)
          id = identifiant!(reference, "séjour")
          Stay.includes(:customer, stay_items: :bookable).find_by(id: id) ||
            raise(Base::Error, "Aucun séjour ##{id} (ou il a été supprimé).")
        end

        def identifiant!(reference, quoi)
          Integer(reference.to_s.delete("#").strip)
        rescue ArgumentError
          raise Base::Error, "Identifiant de #{quoi} illisible : « #{reference} »."
        end

        # Un client par son identifiant, son e-mail exact, ou une recherche
        # (nom, organisation, téléphone). Plusieurs candidats : on refuse et on
        # les liste, plutôt que de rattacher au mauvais client.
        def client!(reference)
          reference = reference.to_s.strip
          raise Base::Error, "Précise le client (identifiant, e-mail ou nom)." if reference.empty?

          if reference.delete("#").match?(/\A\d+\z/)
            return Customer.find_by(id: reference.delete("#")) || raise(Base::Error, "Aucun client #{reference}.")
          end

          par_email = Customer.find_by(email: Customer.normalize_email(reference))
          return par_email if par_email

          candidats = Customer.search(reference).order(:last_name, :first_name).limit(11).to_a
          return candidats.first if candidats.size == 1
          raise Base::Error, "Aucun client ne correspond à « #{reference} »." if candidats.empty?

          raise Base::Error, "Plusieurs clients correspondent à « #{reference} » : " \
                             "#{candidats.first(10).map { |c| ligne_client(c) }.join(' ; ')}. Précise l'identifiant."
        end

        def ligne_client(client)
          contact = [client.email.presence, client.phone.presence].compact.join(", ")
          "##{client.id} #{client.name}#{" (#{contact})" if contact.present?}"
        end

        def dates(stay)
          return "sans dates" if stay.arrival_date.blank? && stay.departure_date.blank?
          return stay.arrival_date.to_s if stay.arrival_date == stay.departure_date

          nuits = stay.arrival_date && stay.departure_date ? (stay.departure_date - stay.arrival_date).to_i : nil
          "#{stay.arrival_date || '?'} → #{stay.departure_date || '?'}#{" (#{nuits} nuit#{'s' if nuits > 1})" if nuits&.positive?}"
        end

        def nom_sejour(stay)
          stay.decorate.display_name.presence || "client ##{stay.customer_id}"
        end

        def statut(stay)
          STATUTS.fetch(stay.status.to_s, stay.status.presence || "sans statut")
        end

        # Une ligne par séjour : de quoi le reconnaître et le désigner ensuite.
        def ligne_sejour(stay, montant = nil)
          paye = montant ? montant.paid_cents : stay.amount_paid_cents
          reste = montant ? montant.balance_due_cents : stay.balance_due_cents
          categorie = stay.category_label ? " · #{stay.category_label}" : ""
          "##{stay.id}  #{dates(stay)}  #{nom_sejour(stay)}#{categorie} · #{statut(stay)} · " \
            "total #{euros(stay.total_amount_cents)}, payé #{euros(paye)}, reste #{euros(reste)} · " \
            "#{stay.decorate.composition_summary}"
        end

        # L'état du séjour que signe une confirmation : s'il bouge entre
        # l'aperçu et l'accord (quelqu'un l'a modifié dans l'interface), le
        # code ne vaut plus.
        def etat(stay)
          [stay.id, stay.updated_at&.utc&.iso8601(6), stay.status]
        end

        # Les arguments réduits à ce qui décide de l'écriture, dans un ordre
        # stable : Claude peut les renvoyer dans un autre ordre à la confirmation.
        def arguments_signes(arguments)
          trier = lambda do |valeur|
            case valeur
            when Hash then valeur.except("motif", "confirmation").sort.to_h { |cle, v| [cle, trier.call(v)] }
            when Array then valeur.map { |v| trier.call(v) }
            else valeur
            end
          end
          trier.call(arguments)
        end

        # Prix imposé en euros : 0 est un vrai prix, « aucun » le retire.
        def prix_impose(valeur)
          return nil if valeur.nil? || valeur.to_s.strip.match?(/\A(|aucun|non|null)\z/i)

          texte = valeur.to_s.strip.delete(" €").tr(",", ".")
          raise Base::Error, "prix_impose : montant illisible « #{valeur} »." unless texte.match?(/\A\d+(\.\d{1,2})?\z/)

          (BigDecimal(texte) * 100).to_i
        end

        def email_client(stay)
          client = stay.customer
          return nil if client.nil? || client.catch_all? || !Customer.exploitable_email?(client.email)

          client.email
        end

        def avertissements_cuisine(stay)
          stay.meal_orders.active.flat_map { |repas| repas.warnings.map { |w| "⚠ Cuisine, #{repas.label} du #{repas.date} : #{w}." } }
        end
      end
    end
  end
end
