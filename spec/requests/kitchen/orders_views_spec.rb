require "rails_helper"

# Les deux vues de la page Cuisine (2026-10-19) : Cuisine pour Stéphanie,
# Accueil pour Malau. Elles remplacent sept onglets qui se recoupaient — le même
# repas était dans trois onglets à la fois. Chaque vue montre toutes les
# demandes à venir, une seule fois, rangées par statut.
RSpec.describe "Cuisine — vues Cuisine et Accueil", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-vues@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph-vues@les4sources.be", status: "active") }
  let!(:malau) { Human.create!(name: "Malau", email: "malau-vues@les4sources.be", status: "active") }
  let(:customer) { Customer.create!(email: "client-vues@example.com", first_name: "Groupe", last_name: "Scout") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "confirmed") }

  before { sign_in user }

  def order(**attrs)
    stay.meal_orders.create!({ kind: "repas", people: 10, date: Date.current + 10, responsible_human: steph }.merge(attrs))
  end

  def doc = Nokogiri::HTML(response.body)

  def section_ids(status)
    doc.css("#section-#{status} tr[id^=order-]").map { |tr| tr["id"].delete_prefix("order-").to_i }
  end

  def section_order = doc.css("section[id^=section-]").map { |s| s["id"].delete_prefix("section-") }

  let!(:a_valider) { order(validation: "pending") }
  let!(:info)      { order(status: "inquiry", validation: "accepted", date: Date.current + 11) }
  let!(:prevu)     { order(status: "requested", validation: "accepted", date: Date.current + 12) }
  let!(:a_couvrir) { order(validation: "refused", refusal_reason: "En congé", date: Date.current + 13) }

  describe "le statut affiché" do
    it "range chaque demande dans une seule section" do
      get kitchen_orders_path(view: :kitchen)

      expect(section_ids("to_validate")).to eq([a_valider.id])
      expect(section_ids("inquiry")).to eq([info.id])
      expect(section_ids("planned")).to eq([prevu.id])
      expect(section_ids("to_cover")).to eq([a_couvrir.id])
      expect(doc.css("tr[id^=order-]").size).to eq(4)
    end

    it "garde ferme et confirmé ensemble dans « Prévu », avec leur pastille" do
      confirme = order(status: "confirmed", validation: "accepted", date: Date.current + 14)

      get kitchen_orders_path(view: :reception)
      expect(section_ids("planned")).to contain_exactly(prevu.id, confirme.id)
      planned = CGI.unescapeHTML(doc.at_css("#section-planned").to_html)
      expect(planned).to include("Ferme", "Confirmé")
    end
  end

  describe "l'ordre des sections" do
    it "commence par ce que la cuisine doit faire dans la vue Cuisine" do
      get kitchen_orders_path(view: :kitchen)
      expect(section_order).to eq(%w[to_validate planned inquiry to_cover])
    end

    it "commence par ce que l'accueil doit faire dans la vue Accueil" do
      get kitchen_orders_path(view: :reception)
      expect(section_order).to eq(%w[to_cover inquiry to_validate planned])
    end
  end

  describe "les gestes" do
    it "propose « Ok ! » et « Pas possible » à la cuisine, pas à l'accueil" do
      get kitchen_orders_path(view: :kitchen)
      expect(doc.at_css("#order-#{a_valider.id}").text).to include("Ok !", "Pas possible")

      get kitchen_orders_path(view: :reception)
      expect(doc.at_css("#order-#{a_valider.id}").text).not_to include("Ok !")
      expect(doc.at_css("#order-#{a_valider.id}").text).to include("Réponse de Stéphanie")
    end

    it "propose « Demande ferme » sur une demande d'info et « Confirmer » sur une demande ferme, côté Accueil" do
      get kitchen_orders_path(view: :reception)
      expect(doc.at_css("#order-#{info.id}").text).to include("Demande ferme")
      expect(doc.at_css("#order-#{prevu.id}").text).to include("Confirmer")
    end
  end

  describe "« Prévu » dans la vue Cuisine" do
    it "se lit jour par jour, avec les convives du jour" do
      jour = prevu.date
      order(status: "confirmed", validation: "accepted", date: jour, moment: "soir", people: 8)

      get kitchen_orders_path(view: :kitchen)
      planned = CGI.unescapeHTML(doc.at_css("#section-planned").to_html)
      expect(planned).to include(I18n.l(jour, format: "%A %-d %B").capitalize, "18 convives", "2 services")
    end

    it "reste une liste par date dans la vue Accueil" do
      get kitchen_orders_path(view: :reception)
      expect(doc.at_css("#section-planned").text).not_to include("convives")
    end
  end

  describe "le sélecteur" do
    it "compte ce que chaque métier a à faire" do
      get kitchen_orders_path(view: :kitchen)
      nav = doc.at_css("nav[aria-label=Vue]").text
      expect(nav).to include("1 à valider", "2 à traiter")
    end

    it "retient la dernière vue ouverte" do
      get kitchen_orders_path(view: :reception)
      get kitchen_orders_path
      expect(doc.at_css("nav[aria-label=Vue] a[aria-current=page]").text).to include("Accueil")
    end

    it "ouvre la vue Cuisine par défaut, et pour un ancien onglet" do
      get kitchen_orders_path(view: :upcoming)
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("nav[aria-label=Vue] a[aria-current=page]").text).to include("Cuisine")
    end
  end

  describe "« À couvrir » → « Confier à… »" do
    it "rouvre la demande pour la nouvelle personne et la prévient" do
      ActionMailer::Base.deliveries.clear
      patch assign_kitchen_order_path(a_couvrir), params: { human_id: malau.id }

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([malau.email])
      expect(mail.subject).to include("Repas")

      a_couvrir.reload
      expect(a_couvrir.responsible_human).to eq(malau)
      expect(a_couvrir.validation).to eq("pending")
      expect(a_couvrir.refusal_reason).to be_nil
      expect(a_couvrir.board_status).to eq("to_validate")
    end
  end
end
