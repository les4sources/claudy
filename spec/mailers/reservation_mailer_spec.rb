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

    context "avec un acompte encore dû (paiement pending)" do
      let!(:deposit) do
        Payment.create!(stay: stay, booking: booking, amount_cents: 37_250,
                        status: "pending", payment_method: "card")
      end

      it "annonce le montant de l'acompte et le lien de paiement direct" do
        html = mail.html_part.body.decoded.gsub(/\s+/, " ")
        text = mail.text_part.body.decoded

        expect(html).to include("372,50 €")
        expect(html).to include("Régler mon acompte")
        [html, text].each do |body|
          expect(body).to include("/payments/#{deposit.id}/pay")
        end
      end
    end

    it "sans acompte dû, replie sur la mention de validation par l'équipe" do
      html = mail.html_part.body.decoded.gsub(/\s+/, " ")

      expect(html).not_to include("Régler mon acompte")
      expect(html).to include("validée par notre équipe")
    end
  end

  describe "#deposit_received (email post-acompte, décision 2026-07-20)" do
    let!(:deposit) do
      Payment.create!(stay: stay, booking: booking, amount_cents: 37_250,
                      status: "paid", payment_method: "card")
    end

    subject(:mail) { described_class.deposit_received(deposit) }

    it "adresse le mail au Customer avec le bon sujet" do
      expect(mail.to).to eq(["guest@example.com"])
      expect(mail.subject).to include("Acompte bien reçu")
    end

    it "confirme le montant reçu et la validation à venir (html ET texte)" do
      html = mail.html_part.body.decoded.gsub(/\s+/, " ")
      text = mail.text_part.body.decoded

      [html, text].each do |body|
        expect(body).to include("372,50 €")
        expect(body).to include("validation par")
        expect(body).to include("/sejour/#{stay.reload.token}")
      end
    end
  end
end
