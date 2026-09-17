require "rails_helper"

# Epic #330, phase 1 — l'activité économique.
#
# Une partie du travail d'un membre est une prestation qui RAPPORTE au lieu de
# consommer le temps collectif. Elle gonflait le compteur « Engagées » et
# faussait le ratio de capacité. Elle sort désormais du budget d'heures du cycle,
# tout en restant visible et comptée à part.
RSpec.describe "Actions de cycle — activité économique (epic #330, phase 1)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "agent-economic@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Chloé", cycle_active: true, roles_enabled: true) }
  let!(:cycle) do
    Cycle.create!(name: "Cycle en cours", start_date: Date.current - 10, end_date: Date.current + 30)
  end

  before { sign_in user }

  def action(**attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: "Action", category: :ponctuelle }.merge(attrs))
  end

  describe "le modèle" do
    it "n'est pas économique par défaut" do
      expect(action).not_to be_economic
    end

    it "se retrouve par ses scopes" do
      eco = action(label: "Prestation", economic: true)
      normale = action(label: "Tondre")

      expect(CycleAction.economic).to contain_exactly(eco)
      expect(CycleAction.non_economic).to contain_exactly(normale)
    end
  end

  describe "PATCH /cycle_actions/:id/toggle_economic" do
    it "bascule le mode, puis le retire" do
      ca = action(hours: 3)

      patch toggle_economic_cycle_action_path(ca), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
      expect(ca.reload).to be_economic

      patch toggle_economic_cycle_action_path(ca), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(ca.reload).not_to be_economic
    end

    it "répond en Turbo Stream avec la ligne, le bloc de charge et le compteur" do
      ca = action(hours: 3)

      patch toggle_economic_cycle_action_path(ca), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("cycle_action_#{ca.id}")
      expect(response.body).to include("hours_total")
      expect(response.body).to include("category_ponctuelle_count")
    end

    it "exige une session" do
      ca = action
      sign_out user

      patch toggle_economic_cycle_action_path(ca)

      expect(response).to redirect_to(new_user_session_path)
      expect(ca.reload).not_to be_economic
    end
  end

  describe "le bloc de charge de la page membre" do
    # Le cœur de la phase : si l'exclusion saute, ce test tombe.
    it "compte 2 h engagées et 3 h économiques, pas 5 h engagées" do
      action(label: "Tondre", hours: 2)
      action(label: "Chantier participatif", hours: 3, economic: true)

      get organisation_member_path(human.id, cycle_id: cycle.id)

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css(".ca-engaged-value").text.strip).to eq("2")
      expect(response.body).to include("Économiques")
      expect(response.body).to include("Hors budget d'heures du cycle")
    end

    it "n'affiche aucun compteur économique quand il n'y en a pas" do
      action(label: "Tondre", hours: 2)

      get organisation_member_path(human.id, cycle_id: cycle.id)

      expect(response.body).not_to include("Hors budget d'heures du cycle")
    end

    it "sort les heures économiques de la répartition par catégorie" do
      action(label: "Rituel", hours: 4, category: :rituelle)
      action(label: "Prestation rituelle", hours: 6, category: :rituelle, economic: true)

      get organisation_member_path(human.id, cycle_id: cycle.id)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css(".ca-engaged-value").text.strip).to eq("4")
      # 4 h en rituelles, pas 10 : la légende de la barre de répartition le dit.
      expect(response.body).to include("Rituelles")
    end

    it "pose data-economic sur la ligne, pour le recalcul après glisser-déposer" do
      eco = action(label: "Chantier", hours: 3, economic: true)

      get organisation_member_path(human.id, cycle_id: cycle.id)

      row = Nokogiri::HTML(response.body).at_css("#cycle_action_#{eco.id}")
      expect(row["data-economic"]).to eq("true")
      expect(row["class"]).to include("ring-amber-400")
    end
  end

  describe "les services de saisie" do
    it "acceptent `economic` à la création" do
      params = ActionController::Parameters.new(
        cycle_action: { label: "Prestation", hours: 3, category: "ponctuelle",
                        human_id: human.id, cycle_id: cycle.id, economic: "1" }
      )
      service = CycleActions::CreateService.new
      expect(service.run(params)).to be(true)
      expect(service.cycle_action).to be_economic
    end

    it "acceptent `economic` à l'édition" do
      ca = action(hours: 3)
      params = ActionController::Parameters.new(cycle_action: { economic: "1" })

      expect(CycleActions::UpdateService.new(cycle_action: ca).run(params)).to be(true)
      expect(ca.reload).to be_economic
    end
  end
end
