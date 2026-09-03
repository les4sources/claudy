require "rails_helper"

RSpec.describe ReservationMailer, type: :mailer do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  let(:booking) do
    b = Booking.new(firstname: "Léa", email: "guest@example.com",
                    from_date: Date.today + 30, to_date: Date.today + 32, adults: 2,
                    status: "pending", lodging_id: lodging.id, price_cents: 74_500, shown_price_cents: 74_500)
    b.generate_token
    b.save!
    b
  end

  let(:stay) do
    s = Stay.create!(customer: customer, source: "reservation", status: "pending",
                     arrival_date: Date.today + 30, departure_date: Date.today + 32,
                     total_amount_cents: 74_500)
    s.stay_items.create!(bookable: booking)
    s
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
      expect(mail.body.encoded).to include("745") # Hulotte 2 nuits = 485 + 260 = 745 €
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

end
