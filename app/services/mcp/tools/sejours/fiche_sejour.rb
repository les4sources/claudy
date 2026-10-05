module Mcp
  module Tools
    module Sejours
      # Tout ce que montre la modale d'un séjour : client, composition,
      # activités, repas, paiements, notes, demande de modification.
      class FicheSejour < Base
        include Commun

        tool "fiche_sejour",
             title: "Fiche d'un séjour",
             description: "Le détail d'un séjour : client et contact, dates et heures, composition (hébergement, " \
                          "espaces, camping, repas, activités, draps), montants, paiements (avec leurs " \
                          "identifiants), notes interne et publique, demande de modification en attente.",
             schema: { properties: { sejour: SEJOUR }, required: %w[sejour] }

        ACTIVITES = { "pending" => "à valider par le porteur", "confirmed" => "validée", "refused" => "refusée",
                      "cancelled" => "annulée" }.freeze

        def call(arguments)
          stay = sejour!(arguments["sejour"])
          deco = stay.decorate
          [entete(stay, deco), composition(stay, deco), argent(stay), notes(stay), demandes(stay)].compact.join("\n\n")
        end

        private

        def entete(stay, deco)
          client = stay.customer
          lignes = ["Séjour ##{stay.id} — #{nom_sejour(stay)}"]
          lignes << "Client : #{ligne_client(client)}#{' [fourre-tout]' if client&.catch_all?}"
          lignes << "Contact d'origine : #{deco.contact_email}" if client&.catch_all? && deco.contact_email
          lignes << "Dates : #{dates(stay)}#{heures(stay)}"
          occupants = deco.occupants
          if occupants[:adults].positive? || occupants[:children].positive?
            lignes << "Personnes : #{occupants[:adults]} adulte(s), #{occupants[:children]} enfant(s)"
          end
          lignes << "Statut : #{statut(stay)} · paiement : #{PAIEMENT_SEJOUR.fetch(stay.payment_status, stay.payment_status)}" \
                    " · facture : #{stay.invoice_status_label}"
          lignes << "Catégorie : #{stay.category_label || 'aucune'} · canal : #{stay.source}#{' (OTA)' if stay.ota?}"
          lignes << "Email de confirmation envoyé le #{I18n.l(stay.confirmation_email_sent_at, format: '%d/%m/%Y %H:%M')}" if stay.confirmation_email_sent_at
          lignes << "Page client : #{page_client(stay)}" if stay.token.present?
          lignes.join("\n")
        end

        def heures(stay)
          heures = [stay.arrival_time.presence && "arrivée #{stay.arrival_time}",
                    stay.departure_time.presence && "départ #{stay.departure_time}"].compact
          heures.any? ? " (#{heures.join(', ')})" : ""
        end

        def composition(stay, deco)
          lignes = stay.stay_items.filter_map(&:bookable).map do |bookable|
            "- #{deco.item_label(bookable)}#{detail_bookable(bookable)} : #{euros(bookable.try(:price_cents))}"
          end
          stay.experience_bookings.includes(experience_availability: :experience).order(:id).each do |activite|
            creneau = activite.experience_availability
            lignes << "- Activité ##{activite.id} #{creneau&.experience&.name} le #{creneau&.available_on} à #{creneau&.starts_at}" \
                      " — #{activite.participants} pers., #{ACTIVITES.fetch(activite.status, activite.status)} : #{euros(activite.price_cents)}"
          end
          stay.meal_orders.order(:date, :id).each do |repas|
            lignes << "- Repas ##{repas.id} #{repas.label} le #{repas.date || '?'} #{repas.moment} — #{repas.people} pers., " \
                      "#{MealOrder::STATUS_LABELS.fetch(repas.status, repas.status)}" \
                      "#{", cuisine : #{MealOrder::VALIDATION_LABELS.fetch(repas.validation, repas.validation)}" if repas.validation.present?} : " \
                      "#{euros(repas.price_cents)}"
          end
          stay.linen_orders.each { |draps| lignes << "- #{draps.label} × #{draps.quantity} : #{euros(draps.price_cents)}" }
          stay.party_reservations.each do |party|
            lignes << "- Pizza Party #{party.held_on} (#{party.persons} pers., #{party.status}) : #{euros(party.price_cents)}"
          end
          return "Composition : vide." if lignes.empty?

          "Composition :\n#{lignes.join("\n")}"
        end

        def detail_bookable(bookable)
          details = []
          details << "#{bookable.from_date} → #{bookable.to_date}" if bookable.try(:from_date)
          if bookable.is_a?(Booking)
            details << "chambres #{bookable.reservations.map { |r| r.room&.name }.uniq.compact.join(', ')}" if bookable.rooms_mode?
            details << "#{bookable.adults.to_i} ad. #{bookable.children.to_i} enf."
            details << "groupe « #{bookable.group_name} »" if bookable.group_name.present?
          end
          details << "#{bookable.people} pers." if bookable.respond_to?(:people) && bookable.people.present?
          details.any? ? " (#{details.join(', ')})" : ""
        end

        def argent(stay)
          lignes = ["Total : #{euros(stay.total_amount_cents)}#{' (prix imposé)' if stay.price_overridden?} · " \
                    "exigible : #{euros(stay.payable_amount_cents)} · payé : #{euros(stay.amount_paid_cents)} · " \
                    "reste dû : #{euros(stay.balance_due_cents)}"]
          paiements = stay.payments.order(:created_at).to_a
          lignes << (paiements.empty? ? "Aucun paiement." : "Paiements :")
          paiements.each do |paiement|
            lignes << "- Paiement ##{paiement.id} #{euros(paiement.amount_cents)} · #{METHODES.fetch(paiement.payment_method.to_s, paiement.payment_method)}" \
                      " · #{STATUTS_PAIEMENT.fetch(paiement.status.to_s, paiement.status)}" \
                      "#{" le #{paiement.paid_on}" if paiement.paid_on}#{' (via la réservation d\'origine)' if paiement.stay_id != stay.id}"
          end
          lignes.join("\n")
        end

        def notes(stay)
          interne = stay.internal_note_text
          publique = stay.public_notes.to_plain_text.strip
          blocs = []
          blocs << "Note interne :\n#{interne}" if interne.present?
          blocs << "Note publique (visible du client) :\n#{publique}" if publique.present?
          blocs.presence&.join("\n\n")
        end

        def demandes(stay)
          demande = stay.stay_change_requests.pending.order(:created_at).last
          return nil unless demande

          "Demande de modification ##{demande.id} en attente (#{I18n.l(demande.created_at, format: '%d/%m/%Y')}) : " \
            "nouveau total #{euros(demande.new_total_cents)} (#{demande.delta_cents.to_i.positive? ? '+' : ''}#{euros(demande.delta_cents)})" \
            "#{" — remboursement attendu de #{euros(demande.overpaid_cents)}" if demande.refund_expected?}\n" \
            "Proposition : #{resume_proposition(demande)}"
        end

        def resume_proposition(demande)
          draft = demande.proposed_draft
          morceaux = ["#{draft.arrival_date} → #{draft.departure_date}"]
          morceaux << draft.lodging.name if draft.lodging
          morceaux << "#{draft.adults} ad. #{draft.children} enf." if draft.adults.to_i.positive?
          morceaux << draft.quote.lines.map { |l| "#{l.label} #{euros(l.amount_cents)}" }.join(", ")
          morceaux.compact_blank.join(" · ")
        rescue StandardError
          "voir la fiche dans Claudy"
        end

        def page_client(stay)
          options = ActionMailer::Base.default_url_options
          helpers = Rails.application.routes.url_helpers
          options[:host].present? ? helpers.public_stay_url(stay.token, **options) : helpers.public_stay_path(stay.token)
        end
      end
    end
  end
end
