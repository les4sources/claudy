require "rails_helper"

RSpec.describe "Customers (admin Pôle Accueil)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:customer) do
    Customer.create!(email: "admin@example.com", first_name: "Admin", last_name: "Client",
                     customer_type: "individual")
  end

  describe "GET /customers" do
    it "lists customers and supports search" do
      Customer.create!(email: "needle@example.com", first_name: "Needle", customer_type: "individual")
      get customers_path, params: { q: "needle" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("needle@example.com")
    end
  end

  # Assainissement de l'historique clients (epic « liste des clients ») :
  # tri par nombre de séjours, filtre par type, colonne « séjours à venir »,
  # pagination à 100. Les compteurs se calculent en SQL (LEFT JOIN + COUNT +
  # FILTER), séjours soft-deletés exclus, sans N+1.
  describe "GET /customers — tri, filtre, compteurs, pagination" do
    def customer_row(customer_id)
      Nokogiri::HTML(response.body).at_css("#customer_#{customer_id}")
    end

    describe "tri par nombre de séjours vivants" do
      let!(:few) { Customer.create!(email: "few@example.com", customer_type: "individual") }
      let!(:many) { Customer.create!(email: "many@example.com", customer_type: "individual") }

      before do
        Stay.create!(customer: few, arrival_date: Date.today + 1, departure_date: Date.today + 2)
        2.times do |i|
          Stay.create!(customer: many, arrival_date: Date.today + i + 1, departure_date: Date.today + i + 2)
        end
        # Un séjour soft-deleté sur `few` ne doit PAS gonfler son compteur.
        dead = Stay.create!(customer: few, arrival_date: Date.today + 5, departure_date: Date.today + 6)
        dead.destroy
      end

      it "ordonne desc par défaut quand le tri est actif, séjours soft-deletés exclus" do
        get customers_path, params: { sort: "stays", direction: "desc" }
        expect(response).to have_http_status(:ok)
        # `many` (2 séjours) avant `few` (1 séjour vivant, le soft-deleté ne compte pas).
        expect(response.body.index("many@example.com")).to be < response.body.index("few@example.com")
        expect(customer_row(few.id).at_css("[data-role=total-stays]").text.strip).to eq("1")
      end

      it "inverse en ordre asc au 2e clic" do
        get customers_path, params: { sort: "stays", direction: "asc" }
        expect(response.body.index("few@example.com")).to be < response.body.index("many@example.com")
      end
    end

    describe "filtre par type de client" do
      let!(:org) do
        Customer.create!(email: "org@example.com", customer_type: "organization", organization_name: "ACME")
      end

      it "n'affiche que les organisations quand type=organization" do
        get customers_path, params: { type: "organization" }
        expect(response.body).to include("org@example.com")
        expect(response.body).not_to include("admin@example.com") # individual masqué
      end

      it "n'affiche que les particuliers quand type=individual" do
        get customers_path, params: { type: "individual" }
        expect(response.body).to include("admin@example.com")
        expect(response.body).not_to include("org@example.com")
      end
    end

    describe "colonne séjours à venir" do
      let!(:mix) { Customer.create!(email: "mix@example.com", customer_type: "individual") }

      before do
        Stay.create!(customer: mix, arrival_date: Date.today - 5, departure_date: Date.today - 3) # passé
        Stay.create!(customer: mix, arrival_date: Date.today + 3, departure_date: Date.today + 5) # à venir
      end

      it "compte 1 séjour à venir et 2 séjours au total (un passé + un futur)" do
        get customers_path
        row = customer_row(mix.id)
        expect(row.at_css("[data-role=total-stays]").text.strip).to eq("2")
        expect(row.at_css("[data-role=upcoming-stays]").text.strip).to eq("1")
      end
    end

    describe "pagination à 100 par page" do
      before do
        # `customer` (admin) existe déjà ⇒ 1 + 100 = 101 clients au total.
        100.times { |i| Customer.create!(email: "p#{i}@example.com", customer_type: "individual") }
      end

      it "affiche 100 lignes en page 1 et 1 ligne en page 2" do
        get customers_path
        page1 = Nokogiri::HTML(response.body).css("tbody tr[id^='customer_']")
        expect(page1.size).to eq(100)

        get customers_path, params: { page: 2 }
        page2 = Nokogiri::HTML(response.body).css("tbody tr[id^='customer_']")
        expect(page2.size).to eq(1)
      end
    end
  end

  describe "GET /customers/:id" do
    it "renders the customer page" do
      get customer_path(customer)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /customers/:id/edit + PATCH update" do
    it "updates the internal notes" do
      get edit_customer_path(customer)
      expect(response).to have_http_status(:ok)

      patch customer_path(customer), params: { customer: { notes: "Note Pôle Accueil" } }
      expect(response).to redirect_to(customer_path(customer))
      expect(customer.reload.notes.to_plain_text).to include("Note Pôle Accueil")
    end
  end

  describe "merge flow" do
    let!(:source) { Customer.create!(email: "merge-source@example.com", customer_type: "individual") }
    let!(:target) { Customer.create!(email: "merge-target@example.com", customer_type: "individual") }

    before do
      Stay.create!(customer: source, arrival_date: Date.today + 1, departure_date: Date.today + 2)
    end

    it "previews the merge" do
      get merge_preview_customer_path(source), params: { target_id: target.id }
      expect(response).to have_http_status(:ok)
    end

    it "commits the merge through the service" do
      post merge_commit_customer_path(source), params: { target_id: target.id }
      expect(response).to redirect_to(customer_path(target))
      expect(target.stays.count).to eq(1)
      expect(Customer.find_by(id: source.id)).to be_nil # source soft-deleted
    end
  end

  describe "DELETE /customers/:id (suppression gardée)" do
    it "soft-deletes a customer with no stay and redirects with a notice" do
      orphan = Customer.create!(email: "orphan@example.com", first_name: "Orphelin", customer_type: "individual")

      delete customer_path(orphan)

      expect(response).to redirect_to(customers_path)
      expect(flash[:notice]).to be_present
      expect(Customer.find_by(id: orphan.id)).to be_nil          # soft-deleted (default scope)
      expect(Customer.unscoped.find(orphan.id).deleted_at).to be_present # trace conservée
    end

    it "refuses to delete a customer with a live stay and leaves it intact" do
      kept = Customer.create!(email: "hasstay@example.com", first_name: "Occupé", customer_type: "individual")
      Stay.create!(customer: kept, arrival_date: Date.today + 1, departure_date: Date.today + 2)

      delete customer_path(kept)

      expect(response).to redirect_to(customer_path(kept))
      expect(flash[:alert]).to be_present
      expect(Customer.find_by(id: kept.id)).to be_present        # intact
    end

    it "allows deleting a customer whose only stays are soft-deleted (assainissement)" do
      cleaned = Customer.create!(email: "cleaned@example.com", first_name: "Assaini", customer_type: "individual")
      stay = Stay.create!(customer: cleaned, arrival_date: Date.today + 1, departure_date: Date.today + 2)
      stay.soft_delete!

      delete customer_path(cleaned)

      expect(response).to redirect_to(customers_path)
      expect(Customer.find_by(id: cleaned.id)).to be_nil
    end
  end

  describe "delete affordance on the customer show page" do
    it "shows the destructive button when the customer has no live stay" do
      orphan = Customer.create!(email: "showorphan@example.com", first_name: "Sans", customer_type: "individual")
      get customer_path(orphan)
      expect(response.body).to include("Supprimer ce client")
      expect(response.body).not_to include("Suppression impossible")
    end

    it "hides the button and shows a greyed hint when a live stay blocks deletion" do
      blocked = Customer.create!(email: "showblocked@example.com", first_name: "Avec", customer_type: "individual")
      Stay.create!(customer: blocked, arrival_date: Date.today + 1, departure_date: Date.today + 2)
      get customer_path(blocked)
      expect(response.body).to include("Suppression impossible")
      expect(response.body).not_to include("Supprimer ce client")
    end
  end

  describe "GET /customers/search (autocomplete JSON)" do
    it "returns matching customers as JSON" do
      Customer.create!(email: "michael@semisto.org", first_name: "Michael", last_name: "Hulet", customer_type: "individual")
      Customer.create!(email: "autre@example.com", first_name: "Autre", customer_type: "individual")

      get search_customers_path, params: { q: "hulet" }
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.map { |c| c["email"] }).to include("michael@semisto.org")
      expect(data.map { |c| c["email"] }).not_to include("autre@example.com")
      expect(data.first).to include("id", "name", "email")
    end
  end

  describe "re-ventilation (reassign) from the catch-all" do
    let!(:catch_all) { Customer.create!(email: Customer::CATCH_ALL_EMAIL, first_name: "Client", customer_type: "individual") }
    let!(:keep) { Stay.create!(customer: catch_all, arrival_date: Date.today + 1, departure_date: Date.today + 2) }
    let!(:move) { Stay.create!(customer: catch_all, arrival_date: Date.today + 4, departure_date: Date.today + 5) }

    it "renders the show page with selectable stays and the modal" do
      get customer_path(catch_all)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("stay_ids[]")
      expect(response.body).to include("Assigner la sélection à un client")
    end

    it "renders enriched stay rows (French date, colored status label, contact, details link)" do
      enriched = Stay.create!(customer: catch_all, arrival_date: Date.new(2026, 2, 14),
                              departure_date: Date.new(2026, 2, 15), status: "confirmed")
      booking = Booking.create!(firstname: "Jean", lastname: "Dupont", group_name: "Les Amis",
                                from_date: Date.new(2026, 2, 14), to_date: Date.new(2026, 2, 15),
                                adults: 2, status: "confirmed")
      enriched.stay_items.create!(bookable: booking)

      get customer_path(catch_all)
      expect(response.body).to include("14 février 2026")
      expect(response.body).to include("Confirmé")
      expect(response.body).to include("bg-green-100") # label coloré, pas gris
      expect(response.body).to include("Jean Dupont")
      expect(response.body).to include(stay_path(enriched)) # bouton Détails
    end

    it "assigns selected stays to an existing customer (AC-53)" do
      target = Customer.create!(email: "real@example.com", customer_type: "individual")
      post reassign_customer_path(catch_all), params: { stay_ids: [move.id], target_id: target.id, mode: "existing" }
      expect(response).to redirect_to(customer_path(catch_all))
      expect(target.stays.reload).to contain_exactly(move)
      expect(catch_all.stays.reload).to contain_exactly(keep) # catch-all stays active
    end

    it "creates a new customer on the fly and assigns the stays (AC-54)" do
      expect {
        post reassign_customer_path(catch_all),
             params: { stay_ids: [move.id], mode: "new",
                       new_customer: { email: "fresh@example.com", first_name: "Fresh", customer_type: "individual" } }
      }.to change(Customer, :count).by(1)
      created = Customer.find_by(email: "fresh@example.com")
      expect(created.stays).to contain_exactly(move)
    end

    it "is a no-op when nothing is selected (AC-52)" do
      post reassign_customer_path(catch_all), params: { stay_ids: [], target_id: catch_all.id }
      expect(response).to redirect_to(customer_path(catch_all))
      expect(catch_all.stays.reload.count).to eq(2)
    end

    it "transfers nothing when the new customer email is invalid (AC-54 atomic)" do
      Customer.create!(email: "taken@example.com", customer_type: "individual")
      expect {
        post reassign_customer_path(catch_all),
             params: { stay_ids: [move.id], mode: "new",
                       new_customer: { email: "taken@example.com", customer_type: "individual" } }
      }.not_to change(Customer, :count)
      expect(move.reload.customer_id).to eq(catch_all.id)
      expect(flash[:alert]).to be_present
    end
  end
end
