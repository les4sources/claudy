require "rails_helper"

# Issue #157 — écrans Finances > Catalogue.
RSpec.describe "Finances > Catalogue", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }

  let!(:moinette) do
    item = CatalogItem.create!(name: "Moinette", channel: "bar", category: "Bières", unit: "piece")
    item.catalog_prices.create!(
      active_from: Date.new(2023, 1, 1),
      purchase_price_cents: 191, member_price_cents: 210, public_price_cents: 400
    )
    item
  end

  let!(:avoine) do
    item = CatalogItem.create!(name: "Avoine bio", channel: "grocery", category: "Vracs secs", unit: "kg")
    item.catalog_prices.create!(
      active_from: Date.new(2023, 1, 1),
      purchase_price_cents: 240, reference_price_cents: 295,
      member_price_cents: 280, public_price_cents: 310
    )
    item
  end

  before { sign_in user }

  describe "GET /finance/catalog" do
    it "liste les articles avec leur prix courant" do
      get finance_catalog_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Moinette")
      expect(response.body).to include("Avoine bio")
    end

    it "filtre par canal" do
      get finance_catalog_index_path(channel: "grocery")

      expect(response.body).to include("Avoine bio")
      expect(response.body).not_to include("Moinette")
    end

    it "cherche par nom" do
      get finance_catalog_index_path(q: "moin")

      expect(response.body).to include("Moinette")
      expect(response.body).not_to include("Avoine bio")
    end
  end

  describe "paliers de prix" do
    it "crée un palier et clôt le précédent la veille" do
      post finance_catalog_prices_path(moinette), params: {
        catalog_price: { active_from: "2026-09-01", purchase_price: "2,00", member_price: "2,20", public_price: "4,20" }
      }

      expect(moinette.catalog_prices.count).to eq(2)
      ancien = moinette.catalog_prices.chronological.first
      expect(ancien.active_until).to eq(Date.new(2026, 8, 31))
    end

    # Le critère central : le nouveau palier ne déplace pas le prix de la veille.
    it "ne change pas le prix résolu au 31 août" do
      post finance_catalog_prices_path(moinette), params: {
        catalog_price: { active_from: "2026-09-01", member_price: "2,20" }
      }

      expect(moinette.reload.price_on(Date.new(2026, 8, 31)).member_price_cents).to eq(210)
      expect(moinette.price_on(Date.new(2026, 9, 1)).member_price_cents).to eq(220)
    end

    # Le prix sourcier est AUTOMATIQUE : laissé vide, il se calcule depuis
    # l'achat et la marge du canal.
    it "calcule le prix sourcier quand le champ est laissé vide" do
      Rate.find_or_create_by!(key: "catalog.margin.bar") { |r| r.amount_cents = 10; r.unit = "percent" }
          .rate_versions.create!(amount_cents: 10, active_from: Date.new(2023, 1, 1))

      post finance_catalog_prices_path(moinette), params: {
        catalog_price: { active_from: "2026-09-01", purchase_price: "2,00" }
      }

      expect(moinette.catalog_prices.most_recent_first.first.member_price_cents).to eq(220)
    end

    it "laisse la saisie manuelle gagner sur le calcul" do
      post finance_catalog_prices_path(moinette), params: {
        catalog_price: { active_from: "2026-09-01", purchase_price: "2,00", member_price: "3,50" }
      }

      expect(moinette.catalog_prices.most_recent_first.first.member_price_cents).to eq(350)
    end

    it "refuse clairement quand ni achat ni prix sourcier ne sont donnés" do
      expect {
        post finance_catalog_prices_path(moinette), params: {
          catalog_price: { active_from: "2026-09-01" }
        }
      }.not_to change(CatalogPrice, :count)

      follow_redirect!
      expect(response.body).to include("ne peut pas être calculé")
    end

    it "accepte la virgule décimale et laisse vides les prix non saisis" do
      post finance_catalog_prices_path(avoine), params: {
        catalog_price: { active_from: "2026-09-01", member_price: "2,85" }
      }

      palier = avoine.catalog_prices.most_recent_first.first
      expect(palier.member_price_cents).to eq(285)
      expect(palier.purchase_price_cents).to be_nil
    end
  end

  describe "listes imprimables" do
    # La liste sourcier est affichée AU BAR : le prix d'achat n'a rien à y faire.
    it "n'affiche jamais le prix d'achat sur la liste sourcier" do
      get finance_catalog_print_path(audience: "member")

      expect(response.body).to include("2,10")   # prix sourcier
      expect(response.body).not_to include("1,91") # prix d'achat
      expect(response.body).not_to include("2,95") # prix de référence
    end

    it "affiche les prix publics sur la liste publique" do
      get finance_catalog_print_path(audience: "public")

      expect(response.body).to include("4,00")
      expect(response.body).not_to include("1,91")
    end

    it "n'expose pas non plus la marge par le prix de référence du cellier" do
      get finance_catalog_print_path(audience: "member", channel: "grocery")

      expect(response.body).to include("2,80")
      expect(response.body).not_to include("2,40")
    end
  end

  describe "suggestion de prix" do
    it "renvoie la proposition en JSON" do
      Rate.create!(key: "bar.member_markup", amount_cents: 110, unit: "percent")
           .rate_versions.create!(amount_cents: 110, active_from: Date.new(2023, 1, 1))

      get finance_catalog_suggest_price_path(channel: "bar", purchase: "1,91")

      expect(JSON.parse(response.body)["member_price"]).to eq(2.10)
    end
  end

  describe "suppression" do
    # Soft delete : l'article disparaît des listes, mais les écritures passées
    # gardent leur libellé et leur prix — elles ne dépendent pas de lui.
    it "retire l'article des listes sans le détruire" do
      expect {
        delete finance_catalog_path(moinette)
      }.not_to change { CatalogItem.unscoped.count }

      expect(CatalogItem.where(id: moinette.id)).to be_empty
      expect(CatalogItem.unscoped.find(moinette.id).deleted_at).to be_present
    end

    it "laisse intactes les écritures qui le référencent" do
      household = Household.create!(name: "Chevêche", kind: "resident")
      account = MemberAccount.create!(kind: "household", household: household, name: "Chevêche")
      entry = account.account_entries.create!(entry_date: Date.current, amount_cents: 210,
                                              label: "Moinette", catalog_item_id: moinette.id)

      delete finance_catalog_path(moinette)

      expect(entry.reload.label).to eq("Moinette")
      expect(entry.amount_cents).to eq(210)
    end

    it "propose la suppression depuis la fiche de l'article" do
      get finance_catalog_path(moinette)

      expect(response.body).to include("Supprimer")
      expect(response.body).to include("turbo-confirm")
    end
  end

  describe "sans authentification" do
    it "redirige vers la connexion" do
      sign_out user

      get finance_catalog_index_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
