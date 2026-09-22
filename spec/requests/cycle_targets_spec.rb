require "rails_helper"

# Epic #330, phase 3 — les targets du cycle.
#
# Un cycle porte des actions — ce qu'on fait — mais rien qui dise ce qu'on VISE.
# La target est cette intention : une phrase, une case à cocher, et la
# possibilité de dire à la clôture qui a atteint quoi.
RSpec.describe "Targets de cycle (epic #330, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "agent-targets@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Chloé", cycle_active: true, roles_enabled: true) }
  let!(:cycle) do
    Cycle.create!(name: "Cycle en cours", start_date: Date.current - 10, end_date: Date.current + 30)
  end

  before { sign_in user }

  def target(label: "Finir le potager", **attrs)
    CycleTarget.create!({ human: human, cycle: cycle, label: label }.merge(attrs))
  end

  describe "le modèle" do
    it "exige un libellé" do
      expect(CycleTarget.new(human: human, cycle: cycle)).not_to be_valid
    end

    # Une target ajoutée arrive SOUS les précédentes, là où l'œil l'attend.
    it "se place en fin de liste à la création" do
      premiere = target(label: "Une")
      seconde = target(label: "Deux")

      expect(seconde.position).to be > premiere.position
      expect(CycleTarget.ordered.map(&:label)).to eq(%w[Une Deux])
    end

    it "bascule l'atteinte dans les deux sens" do
      t = target

      t.toggle_achieved!
      expect(t.reload).to be_achieved
      expect(t.achieved_at).to be_present

      t.toggle_achieved!
      expect(t.reload).not_to be_achieved
      expect(t.achieved_at).to be_nil
    end

    it "se retrouve par ses scopes" do
      atteinte = target(label: "Atteinte", achieved_at: Time.current)
      target(label: "En cours")

      expect(CycleTarget.achieved).to contain_exactly(atteinte)
      expect(CycleTarget.for_cycle(cycle).count).to eq(2)
    end
  end

  describe "le bloc sur la page membre" do
    it "s'affiche au-dessus des actions, avec un état vide explicite" do
      get organisation_member_path(human.id, cycle_id: cycle.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mes targets")
      expect(response.body).to include("Aucune target pour ce cycle.")
    end

    it "liste les targets du membre avec leur compteur d'atteintes" do
      target(label: "Finir le potager", achieved_at: Time.current)
      target(label: "Reprendre le compost")

      get organisation_member_path(human.id, cycle_id: cycle.id)

      expect(response.body).to include("Finir le potager")
      expect(response.body).to include("Reprendre le compost")
      expect(response.body).to include("1 / 2 atteinte")
    end

    # Les targets d'un autre membre ne sont pas les miennes.
    it "ne montre pas les targets d'un autre membre" do
      autre = Human.create!(name: "Marc", cycle_active: true, roles_enabled: true)
      CycleTarget.create!(human: autre, cycle: cycle, label: "Target de Marc")

      get organisation_member_path(human.id, cycle_id: cycle.id)

      expect(response.body).not_to include("Target de Marc")
    end
  end

  describe "POST /cycle_targets" do
    it "crée la target et renvoie le bloc en Turbo Stream" do
      post cycle_targets_path, params: { human_id: human.id, cycle_id: cycle.id, label: "Planter 30 arbres" },
                               headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("cycle_targets_block")
      expect(response.body).to include("Planter 30 arbres")
      expect(human.cycle_targets.count).to eq(1)
    end

    # Un champ vide n'est pas une erreur à afficher : c'est Entrée dans le vide.
    it "ne crée rien sur un libellé vide, sans crier" do
      post cycle_targets_path, params: { human_id: human.id, cycle_id: cycle.id, label: "  " },
                               headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(human.cycle_targets.count).to eq(0)
    end

    it "redirige vers la page membre en HTML" do
      post cycle_targets_path, params: { human_id: human.id, cycle_id: cycle.id, label: "Planter" }

      expect(response).to redirect_to(organisation_member_path(human.id, cycle_id: cycle.id))
    end
  end

  describe "PATCH /cycle_targets/:id/toggle_achieved" do
    it "coche puis décoche, en renvoyant le bloc" do
      t = target

      patch toggle_achieved_cycle_target_path(t), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("cycle_targets_block")
      expect(t.reload).to be_achieved

      patch toggle_achieved_cycle_target_path(t), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(t.reload).not_to be_achieved
    end
  end

  describe "DELETE /cycle_targets/:id" do
    it "supprime la target et renvoie le bloc" do
      t = target

      delete cycle_target_path(t), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("cycle_targets_block")
      expect(CycleTarget.where(id: t.id)).to be_empty
    end
  end

  describe "un cycle clos" do
    let!(:clos) do
      c = Cycle.create!(name: "Cycle clos", start_date: Date.current - 60, end_date: Date.current - 31)
      c.update!(closed_at: Time.current)
      c
    end

    it "refuse la création" do
      post cycle_targets_path, params: { human_id: human.id, cycle_id: clos.id, label: "Trop tard" },
                               headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("ne se modifient plus")
      expect(CycleTarget.count).to eq(0)
    end

    it "refuse la bascule et la suppression" do
      t = CycleTarget.create!(human: human, cycle: clos, label: "Ancienne target")

      patch toggle_achieved_cycle_target_path(t), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(t.reload).not_to be_achieved

      delete cycle_target_path(t), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(CycleTarget.where(id: t.id)).to be_present
    end

    # Un cycle clos se lit encore : le bloc s'affiche, sans un seul bouton.
    it "affiche les targets en lecture seule sur la page membre" do
      CycleTarget.create!(human: human, cycle: clos, label: "Ancienne target", achieved_at: Time.current)

      get organisation_member_path(human.id, cycle_id: clos.id)

      expect(response.body).to include("Ancienne target")
      expect(response.body).not_to include("Ajouter une target")
    end
  end

  describe "la clôture et le bilan" do
    it "expose targets et targets_achieved sur le rapport du membre" do
      target(label: "Atteinte", achieved_at: Time.current)
      target(label: "Ratée")

      report = Cycles::MemberReport.new(human: human, cycle: cycle)

      expect(report.targets.map(&:label)).to eq(%w[Atteinte Ratée])
      expect(report.targets_achieved.map(&:label)).to eq(["Atteinte"])
    end

    # La page de clôture construit un rapport par membre : les targets se
    # chargent pour tout le cycle, pas une requête par personne.
    it "précharge les targets dans for_cycle" do
      target(label: "Préchargée")

      rapports = Cycles::MemberReport.for_cycle(cycle, humans: [human])

      expect(rapports.first.targets.map(&:label)).to eq(["Préchargée"])
    end

    it "montre les targets sur l'écran de clôture, sans bouton" do
      # La clôture ne liste que les membres qui ont des actions : une target
      # seule ne fait pas apparaître quelqu'un sur cet écran.
      CycleAction.create!(human: human, cycle: cycle, label: "Tondre", category: :ponctuelle, hours: 2)
      target(label: "Finir le potager", achieved_at: Time.current)

      get closing_cycle_path(cycle)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finir le potager")
      expect(response.body).to include("1 / 1 atteinte")
    end

    it "montre les targets sur le bilan du cycle" do
      CycleAction.create!(human: human, cycle: cycle, label: "Tondre", category: :ponctuelle, hours: 2)
      target(label: "Finir le potager")
      cycle.update!(closed_at: Time.current)

      get cycle_path(cycle)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finir le potager")
    end
  end
end
