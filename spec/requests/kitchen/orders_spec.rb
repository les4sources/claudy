require "rails_helper"

# Page Cuisine (epic #219, phase 3) — le tableau de Malau dans Claudy.
RSpec.describe "Cuisine — page et actions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "admin-kitchen-orders@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:michael) { Human.create!(name: "Michael", email: "michael@les4sources.be", status: "active") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "malau-test@example.com", first_name: "Groupe", last_name: "Test") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end

  def line(**attrs)
    stay.meal_orders.create!({ kind: "repas", people: 10, date: Date.current + 20 }.merge(attrs))
  end

  describe "GET /kitchen/orders" do
    it "range chaque demande dans une seule section" do
      todo      = line
      upcoming  = line(validation: "accepted", status: "confirmed", date: Date.current + 21)
      inquiry   = line(status: "inquiry", validation: "accepted", date: Date.current + 22)
      archived  = line(validation: "accepted", date: Date.current - 5)
      cancelled = line(status: "cancelled", cancellation_reason: "Groupe annulé")

      get kitchen_orders_path

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body))
        .to include("À traiter", "À venir", "Demandes d'info", "Archives", "Annulés et refusés")
      # Chaque ligne existe, et la page les groupe sous le nom du client.
      [todo, upcoming, inquiry, archived, cancelled].each { |o| expect(o.reload).to be_persisted }
      expect(response.body).to include("Groupe Test")
    end

    it "filtre par famille et par responsable" do
      repas  = line(responsible_human: steph)
      buffet = line(kind: "buffet_vege", responsible_human: michael, notes: "buffet de michael")

      get kitchen_orders_path(family: "buffet")
      expect(response.body).to include("buffet de michael")

      get kitchen_orders_path(family: "repas")
      expect(response.body).not_to include("buffet de michael")

      get kitchen_orders_path(responsible_human_id: michael.id)
      expect(response.body).to include("buffet de michael")

      get kitchen_orders_path(responsible_human_id: steph.id)
      expect(response.body).not_to include("buffet de michael")
      expect(repas.reload.responsible_human).to eq(steph)
    end
  end

  describe "POST /kitchen/orders" do
    def create_params(**attrs)
      { meal_order: { stay_id: stay.id, kind: "repas", moment: "soir", date: (Date.current + 20).iso8601,
                      people: 12, status: "requested", notes: "sans porc" }.merge(attrs) }
    end

    it "crée une demande de repas qui reste à valider, même avec un responsable" do
      expect { post kitchen_orders_path, params: create_params(responsible_human_id: steph.id) }
        .to change(MealOrder, :count).by(1)

      order = MealOrder.order(:created_at).last
      expect(order.responsible_human).to eq(steph)
      expect(order.validation).to eq("pending") # seule Stéphanie décide de sa disponibilité
      expect(order.price_cents).to eq(18_000)
    end

    it "accepte d'emblée un buffet dont quelqu'un se charge" do
      post kitchen_orders_path, params: create_params(kind: "buffet_vege", responsible_human_id: michael.id)

      order = MealOrder.order(:created_at).last
      expect(order.validation).to eq("accepted")
      expect(order.validated_at).to be_present
    end

    it "laisse un buffet sans responsable en attente" do
      post kitchen_orders_path, params: create_params(kind: "buffet_vege", responsible_human_id: "")

      expect(MealOrder.order(:created_at).last.validation).to eq("pending")
    end

    it "applique le prix unitaire saisi en euros" do
      post kitchen_orders_path, params: create_params(unit_price: "22,50")

      order = MealOrder.order(:created_at).last
      expect(order.unit_price_cents).to eq(2_250)
      expect(order.price_cents).to eq(27_000)
    end
  end

  describe "PATCH /kitchen/orders/:id" do
    it "remet la validation en attente et le dit quand la prestation change" do
      order = line(validation: "accepted", validated_at: Time.current, responsible_human: steph)

      patch kitchen_order_path(order), params: { meal_order: { people: 20 } }

      expect(order.reload.validation).to eq("pending")
      expect(flash[:notice]).to include("revalider")
    end

    it "ne dit rien de tel quand seules les notes changent" do
      order = line(validation: "accepted", validated_at: Time.current)

      patch kitchen_order_path(order), params: { meal_order: { notes: "table ronde" } }

      expect(order.reload.validation).to eq("accepted")
      expect(flash[:notice]).not_to include("revalider")
    end

    # Le coût par prestation ne se saisit plus (epic #269) : les courses se font
    # par lot, la dépense s'affecte en comptabilité. Les colonnes restent en
    # base, mais plus rien ne les écrit — pas même une vieille page ouverte.
    it "ignore un coût envoyé malgré tout" do
      order = line(cost_cents: 1_500, cost_notes: "ancien relevé")

      patch kitchen_order_path(order), params: { meal_order: { cost: "42,10", cost_notes: "courses", notes: "table ronde" } }

      expect(order.reload.notes).to eq("table ronde")
      expect(order.cost_cents).to eq(1_500)
      expect(order.cost_notes).to eq("ancien relevé")
    end
  end

  describe "GET /kitchen/orders — qui s'en charge" do
    # Le raccourci qui assignait le membre du compte connecté a disparu : sur un
    # poste partagé il désignait le poste, pas la personne. « Je m'en charge »
    # ouvre la liste des membres.
    it "propose de se nommer au lieu de déduire du compte connecté" do
      user.update!(human: michael)
      line

      get kitchen_orders_path

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("Je m'en charge")
      expect(response.body).not_to include(%(name="human_id" value="#{michael.id}"))
    end
  end

  # Le champ « Séjour » listait jusqu'à 300 entrées dans un sélecteur natif.
  describe "GET /kitchen/orders/stay_search" do
    def stay_for(customer, **attrs)
      Stay.create!({ customer: customer, source: "manual", status: "confirmed",
                     arrival_date: Date.current + 5, departure_date: Date.current + 7 }.merge(attrs))
    end

    let!(:scouts) do
      Customer.create!(email: "scouts@example.com", customer_type: "organization",
                       organization_name: "Les Scouts de Namur", first_name: "Jean",
                       last_name: "Dupont", phone: "0455 13 61 42")
    end

    it "trouve un séjour par le nom, l'organisation, l'email ou le numéro" do
      target = stay_for(scouts)

      %w[Dupont Scouts scouts@example 0455136142].each do |query|
        get stay_search_kitchen_orders_path(q: query)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).map { |row| row["id"] }).to include(target.id), "raté sur « #{query} »"
      end
    end

    it "rend le nom complet tapé d'un bloc" do
      target = stay_for(scouts)

      get stay_search_kitchen_orders_path(q: "Jean Dupont")

      expect(JSON.parse(response.body).map { |row| row["id"] }).to eq([target.id])
    end

    # `Stay` écrit « canceled » (un seul l) et « declined » : le filtre du
    # sélecteur cherchait « cancelled » et ne retirait donc rien.
    it "écarte les séjours annulés ou refusés" do
      stay_for(scouts, status: "canceled")
      stay_for(scouts, status: "declined")

      get stay_search_kitchen_orders_path(q: "Dupont")

      expect(JSON.parse(response.body)).to be_empty
    end

    it "ne cherche pas sur un seul caractère" do
      stay_for(scouts)

      get stay_search_kitchen_orders_path(q: "D")

      expect(JSON.parse(response.body)).to be_empty
    end

    it "donne de quoi distinguer deux séjours du même client" do
      stay_for(scouts)

      get stay_search_kitchen_orders_path(q: "Dupont")

      row = JSON.parse(response.body).first
      expect(row["label"]).to include("du #{(Date.current + 5).strftime('%-d/%m')}")
      expect(row["group"]).to eq("Les Scouts de Namur")
      expect(row["contact"]).to include("scouts@example.com")
    end
  end

  describe "PATCH /kitchen/orders/:id/assign" do
    it "confie la demande et vaut acceptation pour un buffet" do
      order = line(kind: "buffet_vege")

      patch assign_kitchen_order_path(order), params: { human_id: michael.id }

      expect(order.reload.responsible_human).to eq(michael)
      expect(order.validation).to eq("accepted")
    end

    it "confie un repas sans court-circuiter la validation de Stéphanie" do
      order = line

      patch assign_kitchen_order_path(order), params: { human_id: steph.id }

      expect(order.reload.responsible_human).to eq(steph)
      expect(order.validation).to eq("pending")
    end

    # Les postes sont partagés sous un compte commun : même quand le compte
    # connecté est rattaché à un membre, il ne dit pas qui est devant l'écran.
    it "refuse d'assigner sans nommer personne, même si le compte a un membre" do
      user.update!(human: michael)
      order = line

      patch assign_kitchen_order_path(order)

      expect(order.reload.responsible_human).to be_nil
      expect(flash[:alert]).to include("Choisissez qui s'en charge")
    end
  end

  # Deux métiers se croisent sur la même demande et tout tenait dans une seule
  # rangée : « chacun se pose la question de savoir sur quoi je dois cliquer »
  # (retour d'usage Michael). Chaque métier a maintenant sa bande.
  describe "GET /kitchen/orders — séparation cuisine / accueil" do
    it "range chaque action dans la bande du métier qui la porte" do
      line(kind: "buffet_vege", status: "inquiry")

      get kitchen_orders_path

      body = CGI.unescapeHTML(response.body)
      expect(body).to include(">Cuisine</span>", ">Pôle Accueil</span>")

      cuisine = body.split(">Cuisine</span>", 2).last.split(">Pôle Accueil</span>", 2).first
      accueil = body.split(">Pôle Accueil</span>", 2).last

      expect(cuisine).to include("C'est possible", "Pas possible", "Je m'en charge", "Liste de courses")
      expect(cuisine).not_to include("Confirmer", "Modifier")

      expect(accueil).to include("Ferme", "Confirmer", "Modifier", "Annuler")
      expect(accueil).not_to include("C'est possible", "Liste de courses")
    end

    # Une demande annulée ne se cuisine plus : la bande cuisine disparaît, seule
    # la correction reste côté accueil.
    it "ne montre plus la bande cuisine sur une demande annulée" do
      line(status: "cancelled", cancellation_reason: "Groupe annulé")

      get kitchen_orders_path(section: "cancelled")

      body = CGI.unescapeHTML(response.body)
      expect(body).not_to include(">Cuisine</span>")
      expect(body).to include(">Pôle Accueil</span>", "Modifier")
    end
  end

  describe "PATCH /kitchen/orders/:id/status" do
    it "passe une demande d'info en ferme puis en confirmé" do
      order = line(status: "inquiry")

      patch status_kitchen_order_path(order), params: { status: "requested" }
      expect(order.reload.status).to eq("requested")

      patch status_kitchen_order_path(order), params: { status: "confirmed" }
      expect(order.reload.status).to eq("confirmed")
    end

    it "exige un motif pour annuler" do
      order = line

      patch status_kitchen_order_path(order), params: { status: "cancelled" }
      expect(order.reload.status).not_to eq("cancelled")
      expect(flash[:alert]).to include("motif")

      patch status_kitchen_order_path(order), params: { status: "cancelled", cancellation_reason: "Groupe annulé" }
      expect(order.reload.status).to eq("cancelled")
      expect(order.cancellation_reason).to eq("Groupe annulé")
    end
  end

  describe "GET /kitchen/orders/new et /:id/edit" do
    # Le type était préréglé sur le premier type activé, et le responsable sur le
    # défaut de CE type. Basculer le type sans toucher au responsable laissait un
    # buffet au nom de Stéphanie, et ACCEPTÉ par la cuisine sans que personne ne
    # l'ait accepté. Plus rien n'est prérempli : le type se coche.
    it "présélectionne le séjour, mais ni le type ni le responsable" do
      Setting.set("kitchen.repas.default_human_id", steph.id)

      get new_kitchen_order_path(stay_id: stay.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Groupe Test")
      expect(response.body).not_to include(%(selected="selected" value="#{steph.id}"))
      expect(response.body).not_to include(%(name="meal_order[kind]" checked))
      expect(response.body).not_to match(/checked="checked"[^>]*name="meal_order\[kind\]"/)
    end

    it "ne fait plus accepter un buffet au nom du responsable par défaut" do
      Setting.set("kitchen.buffet.default_human_id", michael.id)

      post kitchen_orders_path, params: {
        meal_order: { stay_id: stay.id, kind: "buffet_vege", people: 12,
                      date: Date.current + 20, status: "requested" }
      }

      order = MealOrder.order(:id).last
      expect(order.kind).to eq("buffet_vege")
      expect(order.responsible_human).to eq(michael)
      expect(order.validation).to eq("pending")
    end

    it "affiche l'historique de la ligne" do
      order = line
      order.update!(people: 14)

      get edit_kitchen_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Historique", "Convives")
    end
  end

  describe "fiche séjour" do
    it "montre le bloc Cuisine et le lien d'ajout" do
      line(notes: "deux véganes")

      get stay_path(stay)

      expect(response.body).to include("Cuisine", "deux véganes")
      expect(response.body).to include("/kitchen/orders/new?stay_id=#{stay.id}")
    end
  end
end
