require "rails_helper"

# Issue #155 — écrans Finances > Ménages.
RSpec.describe "Finances > Ménages", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }

  before { sign_in user }

  describe "GET /finance/households" do
    it "liste les ménages avec leur composition du jour" do
      household = Household.create!(name: "Famille Chevêche", kind: "resident",
                                    moved_in_on: Date.new(2023, 1, 1))
      household.household_members.create!(name: "Ada", kind: "adult", started_on: Date.new(2023, 1, 1))
      household.household_members.create!(name: "Zoé", kind: "child", started_on: Date.new(2023, 1, 1))

      get finance_households_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Famille Chevêche")
      expect(response.body).to include("Habitant")
    end
  end

  describe "création" do
    it "crée un ménage avec deux adultes et un enfant" do
      expect {
        post finance_households_path, params: {
          household: {
            name: "Famille Chevêche",
            kind: "resident",
            moved_in_on: "2023-01-01",
            household_members_attributes: {
              "0" => { name: "Ada", kind: "adult", started_on: "2023-01-01" },
              "1" => { name: "Bob", kind: "adult", started_on: "2023-01-01" },
              "2" => { name: "Zoé", kind: "child", started_on: "2025-03-12" }
            }
          }
        }
      }.to change(Household, :count).by(1)

      household = Household.last
      expect(household.household_members.count).to eq(3)
      expect(household.adults_on(Date.new(2026, 1, 1))).to eq(2)
      expect(household.children_on(Date.new(2026, 1, 1))).to eq(1)
      expect(response).to redirect_to(finance_household_path(household))
    end

    it "ignore les lignes de membre laissées vides" do
      post finance_households_path, params: {
        household: {
          name: "Famille Hulotte", kind: "member",
          household_members_attributes: {
            "0" => { name: "Ada", kind: "adult", started_on: "2023-01-01" },
            "1" => { name: "", kind: "adult", started_on: "" },
            "2" => { name: "", kind: "adult", started_on: "" }
          }
        }
      }

      expect(Household.last.household_members.count).to eq(1)
    end

    it "refuse un ménage sans nom" do
      expect {
        post finance_households_path, params: { household: { name: "", kind: "resident" } }
      }.not_to change(Household, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Le builder rangeait l'erreur au MÊME endroit que le texte d'aide, et
    # l'aide gagnait : un champ avec `hint:` — c'est le cas du nom du ménage —
    # ne montrait jamais pourquoi il était refusé, et l'utilisatrice revenait
    # sur le formulaire sans la moindre explication.
    it "dit POURQUOI il refuse, sous le champ et en tête de formulaire" do
      post finance_households_path, params: { household: { name: "", kind: "resident" } }

      expect(response.body).to include("n'a pas pu être enregistré")
      expect(response.body).to include("hint-error")
      expect(response.body).to include("Nom du ménage doit être rempli(e)")
    end

    # `join` sans séparateur collait les classes : un champ en erreur recevait
    # `rounded-mdborder-red-300`, donc ni coins arrondis ni liseré rouge.
    it "marque visuellement le champ fautif" do
      post finance_households_path, params: { household: { name: "", kind: "resident" } }

      expect(response.body).to include("border-red-300")
      expect(response.body).not_to include("rounded-mdborder")
    end

    # Le formulaire ne rendait que trois lignes vides : un ménage de cinq
    # demandait deux passages, sans que rien ne le dise. Le serveur, lui, n'a
    # jamais eu de plafond — c'est ce que cette spec verrouille, pendant que le
    # bouton « Ajouter une personne » lève la limite côté écran.
    it "crée un ménage de cinq personnes en une seule soumission" do
      members = %w[Ada Bob Chloé Dan Eve].each_with_index.to_h do |name, index|
        [index.to_s, { name: name, kind: index >= 3 ? "child" : "adult", started_on: "2023-01-01" }]
      end

      post finance_households_path, params: {
        household: { name: "Famille Grand-Duc", kind: "resident", household_members_attributes: members }
      }

      household = Household.last
      expect(household.household_members.count).to eq(5)
      expect(household.adults_on(Date.new(2026, 1, 1))).to eq(3)
      expect(household.children_on(Date.new(2026, 1, 1))).to eq(2)
    end

    # Les lignes ajoutées au clic portent un index horodaté, pas 0..n-1 : si le
    # contrôleur les regroupait mal, deux personnes ajoutées de suite n'en
    # feraient qu'une. On rejoue donc des index non contigus.
    it "accepte des index de membres non contigus, comme ceux ajoutés au clic" do
      post finance_households_path, params: {
        household: {
          name: "Famille Hulotte", kind: "resident",
          household_members_attributes: {
            "0" => { name: "Ada", kind: "adult", started_on: "2023-01-01" },
            "17555512340001" => { name: "Bob", kind: "adult", started_on: "2023-01-01" },
            "17555512340002" => { name: "Chloé", kind: "child", started_on: "2023-01-01" }
          }
        }
      }

      expect(Household.last.household_members.pluck(:name)).to match_array(%w[Ada Bob Chloé])
    end
  end

  describe "formulaire" do
    it "rend le gabarit de ligne et le bouton d'ajout" do
      get new_finance_household_path

      expect(response.body).to include('data-controller="nested-form"')
      expect(response.body).to include("Ajouter une personne")
      expect(response.body).to include("household_members_attributes][NEW_RECORD]")
    end

    it "ne rend qu'une seule ligne vierge au départ" do
      get new_finance_household_path

      rows = response.body.scan(/household\[household_members_attributes\]\[\d+\]\[name\]/)
      expect(rows.size).to eq(1)
    end

    # `started_on` est obligatoire : un gabarit qui la laisse vide fait échouer
    # tout le formulaire dès qu'on ajoute quelqu'un sans y penser.
    it "préremplit la date de présence dans le gabarit, comme dans la ligne rendue" do
      household = Household.create!(name: "Famille Chevêche", kind: "resident", moved_in_on: Date.new(2023, 4, 1))

      get edit_finance_household_path(household)

      template = response.body[/<template.*?<\/template>/m]
      expect(template).to include('value="2023-04-01"')
    end
  end

  describe "édition" do
    let(:household) { Household.create!(name: "Famille Chevêche", kind: "resident") }

    it "met à jour le ménage" do
      patch finance_household_path(household), params: {
        household: { name: "Famille Hulotte", kind: "member" }
      }

      expect(household.reload.name).to eq("Famille Hulotte")
      expect(household.kind).to eq("member")
      expect(response).to redirect_to(finance_household_path(household))
    end

    it "clôt la présence d'un membre sans le supprimer" do
      member = household.household_members.create!(name: "Bob", kind: "adult", started_on: Date.new(2023, 1, 1))

      patch finance_household_path(household), params: {
        household: {
          name: household.name, kind: household.kind,
          household_members_attributes: {
            "0" => { id: member.id, name: "Bob", kind: "adult",
                     started_on: "2023-01-01", ended_on: "2024-06-30" }
          }
        }
      }

      expect(member.reload.ended_on).to eq(Date.new(2024, 6, 30))
      expect(household.adults_on(Date.new(2024, 7, 1))).to eq(0)
    end
  end

  describe "suppression" do
    it "refuse de supprimer un ménage qui porte encore un compte" do
      household = Household.create!(name: "Famille Chevêche", kind: "resident")
      MemberAccount.create!(kind: "household", name: "Chevêche", household_id: household.id)

      delete finance_household_path(household)

      expect(Household.find_by(id: household.id)).to be_present
      expect(flash[:alert]).to be_present
    end

    it "supprime un ménage sans compte" do
      household = Household.create!(name: "Famille Chevêche", kind: "resident")

      delete finance_household_path(household)

      expect(Household.find_by(id: household.id)).to be_nil
    end
  end

  describe "sans authentification" do
    it "redirige vers la connexion" do
      sign_out user

      get finance_households_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
