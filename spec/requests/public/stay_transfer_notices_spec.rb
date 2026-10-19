require "rails_helper"

# Michael 2026-10-19 — la page client propose le virement à côté du paiement en
# ligne, avec la communication que l'affectation automatique reconnaît, et le
# client peut signaler qu'il a payé : un email part à la compta.
RSpec.describe "Public::StayTransferNotices (virement sur /sejour/:token)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:customer) do
    Customer.create!(first_name: "Léa", last_name: "Virement", email: "virement@example.com",
                     customer_type: "individual")
  end

  def stay_with(status:)
    s = Stay.create!(customer: customer, status: status, total_amount_cents: 48_500,
                     arrival_date: Date.today + 10, departure_date: Date.today + 12)
    s.stay_items.create!(bookable: Booking.create!(firstname: "Léa", lastname: "Virement",
                                                   from_date: Date.today + 10, to_date: Date.today + 12,
                                                   adults: 2, status: "pending",
                                                   booking_type: "lodging", price_cents: 48_500))
    s
  end

  let(:stay) { stay_with(status: "pre_confirmed") }

  before { ActionMailer::Base.deliveries.clear }

  describe "GET /sejour/:token" do
    it "donne le compte, le montant et la communication que l'affectation reconnaît" do
      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-stay-transfer="true"')
      expect(response.body).to include("BE72 5230 8060 1116")
      expect(response.body).to include(Finance::MatchStay.communication_for(stay))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("public.stays.transfer.notify_cta")))
    end

    it "propose le montant de l'acompte demandé quand un paiement est en attente" do
      Payment.create!(stay: stay, amount_cents: 14_500, status: "pending", payment_method: "card")

      get "/sejour/#{stay.token}"

      transfer = response.body[/data-stay-transfer="true".*?<\/dl>/m]
      expect(transfer).to include("145")
      expect(transfer).not_to include("485")
    end

    it "ne propose rien sur une demande encore en attente" do
      get "/sejour/#{stay_with(status: 'pending').token}"

      expect(response.body).not_to include('data-stay-transfer="true"')
    end

    it "ne propose rien sur un séjour soldé" do
      Payment.create!(stay: stay, amount_cents: 48_500, status: "paid", payment_method: "bank_transfer")

      get "/sejour/#{stay.token}"

      expect(response.body).not_to include('data-stay-transfer="true"')
    end
  end

  describe "POST /sejour/:token/virement-envoye" do
    it "prévient la compta et affiche « virement signalé » au retour" do
      post "/sejour/#{stay.token}/virement-envoye"

      expect(response).to redirect_to("/sejour/#{stay.token}#paiement")
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["compta@les4sources.be"])
      expect(mail.cc).to eq(["sejours@les4sources.be"])
      expect(mail.reply_to).to eq(["virement@example.com"])
      expect(mail.subject).to include("485,00")
      expect(mail.body.decoded).to include(Finance::MatchStay.communication_for(stay))
      expect(stay.reload.transfer_notified_cents).to eq(48_500)

      follow_redirect!
      expect(response.body).to include('data-stay-transfer-notified="true"')
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("public.stays.transfer.notify_cta")))
    end

    it "n'écrit pas deux fois pour le même virement" do
      2.times { post "/sejour/#{stay.token}/virement-envoye" }

      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "repropose le bouton une fois un paiement encaissé, pour le virement suivant" do
      post "/sejour/#{stay.token}/virement-envoye"
      travel 1.minute do
        Payment.create!(stay: stay, amount_cents: 14_500, status: "paid", payment_method: "bank_transfer")
      end

      travel 2.minutes do
        get "/sejour/#{stay.token}"
        expect(response.body).not_to include('data-stay-transfer-notified="true"')

        post "/sejour/#{stay.token}/virement-envoye"
      end
      expect(ActionMailer::Base.deliveries.size).to eq(2)
      expect(stay.reload.transfer_notified_cents).to eq(34_000)
    end

    it "n'écrit à personne sur une demande encore en attente" do
      post "/sejour/#{stay_with(status: 'pending').token}/virement-envoye"

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "répond 404 sur un jeton inconnu" do
      post "/sejour/inconnu/virement-envoye"

      expect(response).to have_http_status(:not_found)
    end
  end
end
