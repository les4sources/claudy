require "rails_helper"

# Finitions du funnel /reservation (Michael, 2026-10-03).
RSpec.describe "Public::Reservations — finitions du funnel", type: :request do
  include ActiveJob::TestHelper

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500, summary: "9 à 16 personnes")
    2.times { |i| l.rooms << Room.create!(name: "Chambre #{i}", level: 1) }
    l.rooms << Room.create!(name: "Laurier (mezzanine)", code: "MEZ", level: 2)
    l
  end

  let(:arrival)   { Date.new(Date.today.year + 1, 3, 10) }
  let(:departure) { arrival + 1 }

  def compose
    post "/reservation/sejour", params: {
      reservation: { arrival_date: arrival.iso8601, departure_date: departure.iso8601, adults: 2 }
    }
    get "/reservation/composer"
  end

  it "écrit l'année une seule fois pour un séjour dans la même année" do
    compose
    expect(response.body).to include("#{arrival.day} mars → #{departure.day} mars #{arrival.year}")
  end

  it "ne compte pas la mezzanine comme une chambre" do
    compose
    expect(response.body).to include("9 à 16 personnes · 2 chambres")
    expect(response.body).not_to include("3 chambres")
  end

  it "dit l'état de chaque nuit en toutes lettres" do
    b = Booking.create!(firstname: "Occ", from_date: arrival, to_date: departure, adults: 1, status: "confirmed")
    hulotte.rooms.each { |r| Reservation.create!(booking: b, room: r, date: arrival) }
    compose

    expect(response.body).to include("Complet")
    expect(response.body).to include("Complet à vos dates")
  end

  it "ne montre plus ni prix ni bûches dans la grille nuit par nuit" do
    compose
    grille = response.body[/data-controller="public--stay-calendar[^"]*".*?<\/table>/m]
    expect(grille).to be_present
    expect(grille).not_to match(/dès\s+\d+\s*€\/nuit/)
  end

  it "affiche les trois offres « Repas & pain » et le catalogue des activités" do
    compose
    expect(response.body).to include("Repas sur demande")
    expect(response.body).to include("15 € par personne")
    expect(response.body).to include("Épicerie sur place")
    expect(response.body).to include("https://tranchesdevie.les4sources.be")
    expect(response.body).to include('name="reservation[activities_note]"')
    expect(response.body).not_to include("Nuitée individuelle")
    expect(response.body).not_to include("pain &amp; épicerie")
  end

  it "parle de réservation, pas de séjour, et n'a plus d'accroche" do
    get "/reservation/sejour"
    expect(response.body).to include("Votre réservation aux 4 Sources")
    expect(response.body).not_to include("Votre séjour aux 4 Sources")
    expect(response.body).not_to include("Quinze hectares")
  end

  # Retours du 2026-10-03 (soir) : les liens vers le site public s'ouvrent dans
  # un nouvel onglet, pour ne pas perdre la composition en cours.
  it "ouvre les tarifs et le catalogue des activités dans un nouvel onglet" do
    compose
    html = Nokogiri::HTML(response.body)

    %w[https://www.les4sources.be/sejours/tarifs https://www.les4sources.be/activites].each do |url|
      link = html.at_css(%(a[href="#{url}"]))
      expect(link).to be_present, "lien #{url} absent"
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to include("noopener")
    end
  end

  it "met en avant, avant l'envoi, que rien n'est prélevé aujourd'hui" do
    post "/reservation/sejour", params: { reservation: { arrival_date: arrival.iso8601, departure_date: departure.iso8601, adults: 2 } }
    get "/reservation/coordonnees"
    html = Nokogiri::HTML(response.body)

    box = html.at_css(".funnel-next-steps")
    expect(box.at_css(".funnel-next-steps__title").text).to include("Rien n'est prélevé aujourd'hui")
    expect(box.css("li").map { |li| li.text.squish }.last).to include("C'est le règlement de cet acompte qui confirme")
    # La boîte vient AVANT le bouton d'envoi : on la lit avant de cliquer.
    expect(response.body.index("funnel-next-steps")).to be < response.body.index("funnel-submit-cta")
  end

  it "ne met plus d'espace à l'intérieur du lien email de l'étape 1" do
    get "/reservation/sejour"
    expect(response.body).not_to include("> sejours@les4sources.be</a>")
    expect(response.body).not_to include("Nuitée individuelle en semaine")
  end

  it "transmet les activités souhaitées avec la demande" do
    perform_enqueued_jobs do
      post "/reservation/coordonnees", params: {
        reservation: {
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          dogs_count: 0, first_name: "Act", email: "act@example.com", phone: "+32 470 11 12 13",
          lodging_night_ids: [hulotte.id],
          activities_note: "Balade avec les ânes pour 6 enfants"
        }
      }
    end

    stay = Stay.last
    expect(stay).to be_present
    expect(stay.internal_notes.to_plain_text).to include("Activités qui intéressent le groupe : Balade avec les ânes pour 6 enfants")
  end

  it "refuse un numéro de téléphone qui n'en est pas un" do
    expect {
      post "/reservation/coordonnees", params: {
        reservation: {
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          first_name: "Tel", email: "tel@example.com", phone: "appelez-moi",
          lodging_night_ids: [hulotte.id]
        }
      }
    }.not_to change(Stay, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Ce numéro ne semble pas complet")
  end

  describe "facture" do
    let(:vies_url) { "https://ec.europa.eu/taxation_customs/vies/rest-api/ms/BE/vat/0123456749" }

    def request_stay(**billing)
      perform_enqueued_jobs do
        post "/reservation/coordonnees", params: {
          reservation: {
            arrival_date: arrival.iso8601, departure_date: departure.iso8601,
            dogs_count: 0, first_name: "Fac", email: "fac@example.com",
            lodging_night_ids: [hulotte.id]
          }.merge(billing)
        }
      end
    end

    let(:billing) do
      { invoice_requested: "1", billing_name: "Atelier Bois SRL", billing_vat: "be 0123.456.749",
        billing_address: "Rue du Bois 12", billing_zip: "5530", billing_city: "Yvoir", billing_country: "BE" }
    end

    it "pose la question à l'étape Coordonnées" do
      post "/reservation/sejour", params: { reservation: { arrival_date: arrival.iso8601, departure_date: departure.iso8601, adults: 2 } }
      get "/reservation/coordonnees"

      expect(response.body).to include("Avez-vous besoin d'une facture ?")
      expect(response.body).to include('name="reservation[billing_vat]"')
    end

    it "transmet les coordonnées vérifiées par VIES et met le séjour en « facture à fournir »" do
      stub_request(:get, vies_url).to_return(status: 200, body: { isValid: true, name: "ATELIER BOIS SRL" }.to_json)

      request_stay(**billing)

      stay = Stay.last
      expect(stay.invoice_status).to eq("requested")
      note = stay.internal_notes.to_plain_text
      expect(note).to include("Facture demandée au nom de : Atelier Bois SRL")
      expect(note).to include("TVA : BE0123456749 (vérifié dans VIES : ATELIER BOIS SRL)")
      expect(note).to include("Adresse : Rue du Bois 12, 5530 Yvoir, Belgique")
      expect(stay.customer.vat_number).to eq("BE0123456749")
      expect(stay.customer.address_city).to eq("Yvoir")
    end

    it "laisse passer la demande quand VIES est injoignable" do
      stub_request(:get, vies_url).to_timeout

      request_stay(**billing)

      expect(Stay.last.internal_notes.to_plain_text).to include("non vérifié, VIES était injoignable")
    end

    it "refuse un numéro de TVA mal formé sans interroger VIES" do
      expect { request_stay(**billing, billing_vat: "BE0123456748") }.not_to change(Stay, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("n&#39;a pas le bon format")
      expect(a_request(:get, /ec\.europa\.eu/)).not_to have_been_made
    end

    it "refuse un numéro que VIES ne connaît pas" do
      stub_request(:get, vies_url).to_return(status: 200, body: { isValid: false, userError: "INVALID" }.to_json)

      expect { request_stay(**billing) }.not_to change(Stay, :count)
      expect(response.body).to include("inconnu du registre européen")
    end

    it "exige la raison sociale, l'adresse et le numéro de TVA" do
      expect { request_stay(invoice_requested: "1", billing_name: "", billing_vat: "") }.not_to change(Stay, :count)
      expect(response.body).to include("Indiquez la raison sociale")
      expect(response.body).to include("Indiquez l&#39;adresse de facturation.")
      expect(response.body).to include("Indiquez le numéro de TVA, ou cochez « Sans numéro de TVA ».")
    end

    it "accepte une facture sans numéro quand la case est cochée" do
      request_stay(**billing, billing_vat: "", billing_no_vat: "1")

      expect(Stay.last.internal_notes.to_plain_text).to include("TVA : sans numéro de TVA (case cochée par le client)")
      expect(a_request(:get, /ec\.europa\.eu/)).not_to have_been_made
    end

    it "annonce l'acompte à la confirmation, pas à la réservation" do
      post "/reservation/devis", params: { reservation: { lodging_night_ids: [hulotte.id], arrival_date: arrival.iso8601, departure_date: departure.iso8601 } },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("% à la confirmation")
      expect(response.body).not_to include("% à la réservation")
    end

    it "ignore les coordonnées quand aucune facture n'est demandée" do
      request_stay(**billing, invoice_requested: "0")

      expect(Stay.last.invoice_status).to be_nil
      expect(Stay.last.internal_notes.to_plain_text).not_to include("Facture demandée")
    end
  end
end
