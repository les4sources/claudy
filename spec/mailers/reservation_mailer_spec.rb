require "rails_helper"

RSpec.describe ReservationMailer, type: :mailer do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  let(:booking) do
    b = Booking.new(firstname: "Léa", email: "guest@example.com",
                    from_date: (Date.today + 30).next_occurring(:monday),
                    to_date: (Date.today + 30).next_occurring(:monday) + 2, adults: 2,
                    status: "pending", lodging_id: lodging.id, price_cents: 74_500, shown_price_cents: 74_500)
    b.generate_token
    b.save!
    b
  end

  let(:stay) do
    s = Stay.create!(customer: customer, source: "reservation", status: "pending",
                     arrival_date: (Date.today + 30).next_occurring(:monday),
                     departure_date: (Date.today + 30).next_occurring(:monday) + 2,
                     total_amount_cents: 74_500)
    s.stay_items.create!(bookable: booking)
    s
  end

  # Issue #232 — un client peut vivre sans email. Chaque mailer porte sa propre
  # garde : on ne compte pas sur les seuls appelants.
  describe "client sans adresse email (issue #232)" do
    let(:customer) { Customer.create!(email: nil, first_name: "Jean", last_name: "Sanmail") }

    it "n'envoie ni la demande de confirmation ni la confirmation de séjour" do
      ActionMailer::Base.deliveries.clear

      expect {
        described_class.confirmation_request(stay).deliver_now
        described_class.stay_confirmed(stay).deliver_now
      }.not_to raise_error

      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "#confirmation_request (AC-T2-21 / AC-T2-17)" do
    subject(:mail) { described_class.confirmation_request(stay) }

    it "adresse le mail au Customer" do
      expect(mail.to).to eq(["guest@example.com"])
    end

    # Stay-first (epic #26, Phase 2) : le lien de consultation pointe désormais
    # sur la page séjour /sejour/:token, plus sur la page booking.
    it "contient le lien token stable vers la page séjour (html ET texte)" do
      # Corps décodé : le quoted-printable coupe les longues lignes, donc un
      # `include` sur `body.encoded` casserait le jeton en deux.
      html = mail.html_part.body.decoded
      text = mail.text_part.body.decoded

      [html, text].each do |body|
        expect(body).to include("/sejour/#{stay.reload.token}")
        expect(body).not_to include("/reservation/#{booking.token}")
      end
    end

    it "affiche le breakdown TVAC issu du même PricingModel que l'UI" do
      expect(mail.body.encoded).to match(/Total TVAC/i)
      # Hulotte, 2 nuits SEMAINE au barème du site (epic #260) : 2 × 400 = 800 €.
      expect(mail.body.encoded).to include("800")
      expect(mail.body.encoded).to match(/pas de TVA en plus/i)
    end

    # Bug 2026-07-20 : deux lignes `|` Slim consécutives se concatènent sans
    # espace (« étéenregistrée ») et `| = "…"` sortait littéralement `= "` dans
    # le corps. On verrouille le rendu réel, espaces normalisés.
    it "rend une prose propre (pas de mots collés ni de `= \"` littéral)" do
      html = mail.html_part.body.decoded.gsub(/\s+/, " ")

      expect(html).to include("Elle est bien enregistrée")
      expect(html).not_to include('= "')
      expect(html).not_to match(/Dates\s*:=/)
    end

    # Issue #215 — cet email part AVANT tout regard humain : il ne doit plus
    # porter ni montant d'acompte ni lien de paiement. Même quand un Payment
    # pending traîne sur le séjour (saisie admin), rien ne doit fuir ici.
    describe "aucune demande d'acompte (issue #215)" do
      let!(:deposit) do
        Payment.create!(stay: stay, booking: booking, amount_cents: 37_250,
                        status: "pending", payment_method: "card")
      end

      it "ne porte ni montant d'acompte ni lien de paiement (html ET texte)" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")
        text = mail.text_part.body.decoded

        [html, text].each do |body|
          expect(body).not_to include("/payments/#{deposit.id}/pay")
          expect(body).not_to match(/acompte de/i)
          expect(body).not_to match(/Régler mon acompte/i)
        end
      end

      it "annonce la pré-confirmation par le Pôle Accueil (html ET texte)" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")
        text = mail.text_part.body.decoded.gsub(/\s+/, " ")

        [html, text].each do |body|
          expect(body).to include("Pôle Accueil")
          expect(body).to include("pré-confirmation")
        end
      end
    end
  end

  # Issue #215 — le SEUL email du flux qui demande de l'argent, envoyé après que
  # le Pôle Accueil a regardé la demande.
  describe "#pre_confirmation" do
    let!(:deposit) do
      Payment.create!(stay: stay, booking: booking, amount_cents: 37_250,
                      status: "pending", payment_method: "card")
    end

    subject(:mail) { described_class.pre_confirmation(deposit) }

    it "adresse le mail au Customer avec un sujet parlant" do
      expect(mail.to).to eq(["guest@example.com"])
      expect(mail.subject).to match(/pré-confirmée/i)
    end

    it "porte le montant de l'acompte, le lien de paiement et le lien séjour (html ET texte)" do
      html = mail.html_part.body.decoded.gsub(/\s+/, " ")
      text = mail.text_part.body.decoded.gsub(/\s+/, " ")

      [html, text].each do |body|
        expect(body).to include("372,50 €")
        expect(body).to include("/payments/#{deposit.id}/pay")
        expect(body).to include("/sejour/#{stay.reload.token}")
      end
    end

    it "dit explicitement que le paiement de l'acompte confirme la réservation" do
      html = mail.html_part.body.decoded.gsub(/\s+/, " ")
      text = mail.text_part.body.decoded.gsub(/\s+/, " ")

      [html, text].each do |body|
        expect(body).to match(/règlement de cet acompte qui confirme/i)
      end
    end
  end

  # Malau, 2026-08-20 — le 3e email du flux : « votre séjour est confirmé ».
  describe "#stay_confirmed" do
    subject(:mail) { described_class.stay_confirmed(stay) }

    before { stay.update!(status: "confirmed") }

    it "adresse le mail au Customer" do
      expect(mail.to).to eq(["guest@example.com"])
      expect(mail.subject).to include("confirmé")
    end

    it "porte le lien vers la page séjour (html ET texte)" do
      html = mail.html_part.body.decoded
      text = mail.text_part.body.decoded

      [html, text].each do |body|
        expect(body).to include("/sejour/#{stay.reload.token}")
      end
    end

    it "récapitule la composition et le total" do
      html = mail.html_part.body.decoded
      expect(html).to include("La Hulotte")
      expect(html).to include("745")
    end

    it "récapitule aussi les activités, en marquant celles qui restent à confirmer" do
      experience = Experience.create!(name: "Balade avec les ânes", fixed_price_cents: 4_500, price_cents: 0)
      availability = ExperienceAvailability.create!(experience: experience, available_on: Date.today + 31, starts_at: "10:00")
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 4, status: "pending")
      stay.recompute_aggregates!

      html = described_class.stay_confirmed(stay.reload).html_part.body.decoded
      expect(html).to include("Balade avec les ânes")
      expect(html).to include("à confirmer")
    end

    it "renvoie vers Tranches de Vie pour le pain et la Pizza Party" do
      html = mail.html_part.body.decoded
      text = mail.text_part.body.decoded

      [html, text].each do |body|
        expect(body).to include("tranchesdevie.les4sources.be")
      end
      expect(html).to include("Pizza Party")
    end

    it "annonce le solde restant dû quand il y en a un" do
      html = mail.html_part.body.decoded
      expect(html).to include("Reste à régler")
    end
  end

  # Décision Michael du 2026-09-08. Un séjour gîte + salle : la composition la
  # plus simple qui prend en défaut l'ancien devis de l'email client (rebâti
  # depuis le seul gîte) ET qui justifie l'email d'équipe — une salle demandée
  # ne se lit nulle part dans l'accusé de réception client.
  describe "demande entrante gîte + salle" do
    let!(:hulotte) do
      lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
      lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
      lodging
    end
    let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

    let(:arrival)   { (Date.today + 50).next_occurring(:monday) }
    let(:departure) { arrival + 2 }

    # On passe par le Builder, pas par des `create!` à la main : c'est LUI qui
    # écrit la note d'espaces préfixée et rattache le SpaceBooking au séjour. Un
    # montage manuel testerait une composition que la production ne produit pas.
    let(:built_stay) do
      draft = Reservations::Draft.new(
        lodging_id: hulotte.id,
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        dogs_count: 0, adults: 2,
        first_name: "Camille", last_name: "Martin",
        email: "camille@example.com", phone: "+32470000000",
        group_name: "Les Copains", category: "friends",
        spaces_note: "Merci de prévoir la salle pour un atelier.",
        halls: [{ kind: "petite_salle", date: arrival.iso8601, period: "journee" }]
      )
      builder = Reservations::Builder.new(draft: draft)
      raise builder.error_message(default: "Builder KO") unless builder.run

      builder.stay.reload
    end

    describe "#team_new_request" do
      subject(:mail) { described_class.team_new_request(built_stay) }

      it "part vers sejours@, sans le doublon de la copie cachée par défaut" do
        expect(mail.to).to eq([ReservationMailer::TEAM_EMAIL])
        expect(mail.bcc).to be_blank
      end

      it "porte un objet qui suffit à trier la boîte sans ouvrir l'email" do
        expect(mail.subject).to include("Nouvelle demande de séjour ##{built_stay.id}")
        expect(mail.subject).to include("Camille Martin (Les Copains)")
        expect(mail.subject).to include("·")
      end

      it "détaille client, occupants et composition — ligne de salle comprise" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")
        text = mail.text_part.body.decoded.gsub(/\s+/, " ")

        [html, text].each do |body|
          expect(body).to include("camille@example.com")
          expect(body).to include("+32470000000")
          expect(body).to include("Groupe d")
          expect(body).to include("La Hulotte")
          expect(body).to include("Petite Salle")
          expect(body).to include("2 adulte(s)")
        end
      end

      it "pousse vers la fiche séjour et y renvoie pour TOUTE action" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")
        text = mail.text_part.body.decoded.gsub(/\s+/, " ")

        [html, text].each do |body|
          expect(body).to include("/stays/#{built_stay.id}")
          expect(body).to match(/pré-confirmer/i)
          expect(body).to match(/refuser/i)
        end
        # Un seul bouton : l'email informe, la fiche décide.
        expect(html.scan("Ouvrir la fiche séjour").size).to eq(1)
      end

      it "remonte la précision d'espaces laissée par le client" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")

        expect(html).to include("Merci de prévoir la salle pour un atelier.")
        expect(html).to include(SpaceComposition::SPACES_NOTE_PREFIX.strip)
      end

      it "remonte la note interne du séjour, dont l'avertissement multi-chiens" do
        built_stay.update!(notes: "⚠️ Demande multi-chiens (2)")
        html = described_class.team_new_request(built_stay.reload).html_part.body.decoded

        expect(html).to include("multi-chiens")
      end
    end

    # Bug constaté le 2026-09-08 : le devis de l'email client était rebâti depuis
    # un Draft ne portant QUE `lodging_id` + les dates. Salles, camping, hamacs et
    # chien en tombaient — 1 265 € annoncés pour un séjour à 1 685 €. On
    # reconstruit désormais avec `Stays::DraftReconstructor`, la reconstruction de
    # référence (déjà utilisée par l'édition admin et la modification client).
    describe "#confirmation_request — récap complet" do
      subject(:mail) { described_class.confirmation_request(built_stay) }

      # Le devis étiquette la salle depuis sa CLÉ de pricing (« Petite salle »),
      # là où la fiche et l'email d'équipe affichent le nom de la `Space`
      # (« Petite Salle ») : deux vocabulaires, une seule salle — d'où le match
      # insensible à la casse.
      it "liste la ligne de salle, absente de l'ancien devis" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")
        text = mail.text_part.body.decoded.gsub(/\s+/, " ")

        [html, text].each { |body| expect(body).to match(/petite salle/i) }
      end

      it "totalise exactement le montant du séjour persisté" do
        quote = Stays::DraftReconstructor.call(built_stay).quote

        expect(quote.total_cents).to eq(built_stay.total_amount_cents)
      end

      it "signe l'email comme les autres du flux" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")
        text = mail.text_part.body.decoded.gsub(/\s+/, " ")

        [html, text].each { |body| expect(body).to include("Pour le pôle Accueil des 4 Sources") }
      end
    end
  end
end
