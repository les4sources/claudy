require "rails_helper"

# Le Guide des 4 Sources (Michael, 2026-10-19) : lu par tous les rôles, écrit
# par les Sourciers, chaque page avec son historique.
RSpec.describe "Le Guide des 4 Sources", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:sourcier) { User.create!(email: "michael@les4sources.be", password: "password123", access_roles: %w[sourcier]) }
  let(:kid) { User.create!(email: "kid@les4sources.be", password: "password123", access_roles: %w[kid]) }
  let!(:chapitre) { GuideChapter.create!(title: "Procédures", description: "Les gestes du quotidien") }
  let!(:page) do
    GuidePage.new.tap do |p|
      Guide::SavePage.new(p, user: sourcier).call(guide_chapter_id: chapitre.id, title: "Soumettre une note de frais",
                                                  body: "## Le ticket\n\nDéposer le ticket dans le bac **Admin**.")
    end
  end

  context "en lecture (Kid)" do
    before { sign_in kid }

    it "lit le sommaire et la page, sans les gestes d'écriture" do
      get guide_root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Procédures", "Soumettre une note de frais")
      expect(response.body).not_to include(new_guide_page_path)

      get guide_page_path(page)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<strong>Admin</strong>", "Dernière modification", "michael@les4sources.be")
      expect(response.body).not_to include(edit_guide_page_path(page))
    end

    it "cherche dans le Guide" do
      get guide_root_path(q: "ticket admin")
      expect(response.body).to include("1 page trouvée", "Soumettre une note de frais")
    end

    it "lit l'historique, mais ne modifie rien" do
      get guide_page_revisions_path(page)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Revenir à cette version")

      get edit_guide_page_path(page)
      expect(response).to redirect_to(guide_root_path)

      patch guide_page_path(page), params: { guide_page: { body: "Piraté" } }
      expect(page.reload.body).not_to eq("Piraté")
      post guide_chapters_path, params: { guide_chapter: { title: "Nouveau" } }
      expect(GuideChapter.count).to eq(1)
    end
  end

  it "est ouvert à tous les rôles quand le chapitre les coche tous" do
    chapitre.update!(access_roles: GuideChapter::READER_ROLES)
    Access::ROLE_NAMES.each do |role|
      sign_in User.create!(email: "#{role}@les4sources.be", password: "password123", access_roles: [role])
      get guide_page_path(page)
      expect(response).to have_http_status(:ok), "rôle #{role} : #{response.status}"
    end
  end

  context "en écriture (Sourcier)" do
    before { sign_in sourcier }

    it "crée un chapitre puis une page, la modifie et garde l'historique" do
      post guide_chapters_path, params: { guide_chapter: { title: "Arriver aux 4 Sources" } }
      arriver = GuideChapter.find_by!(title: "Arriver aux 4 Sources")

      get new_guide_page_path(chapter_id: arriver.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="guide-editor"')

      post guide_pages_path, params: { guide_page: { guide_chapter_id: arriver.id, title: "Les clés", body: "Au bureau." } }
      cles = GuidePage.find_by!(title: "Les clés")
      expect(response).to redirect_to(guide_page_path(cles))

      patch guide_page_path(cles), params: { guide_page: { body: "Au bureau, tiroir du haut.", summary: "Précision" } }
      expect(cles.reload.body).to eq("Au bureau, tiroir du haut.")
      expect(cles.revisions.map(&:summary)).to eq(["Précision", nil])

      get guide_page_revisions_path(cles)
      expect(response.body).to include("Version 2", "Précision", "Revenir à cette version")

      post restore_guide_page_revision_path(cles, cles.revisions.last)
      expect(cles.reload.body).to eq("Au bureau.")
      expect(cles.revisions.count).to eq(3)
    end

    it "refuse une page sans titre" do
      post guide_pages_path, params: { guide_page: { guide_chapter_id: chapitre.id, title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "range chapitres et pages au glisser-déposer" do
      autre = GuideChapter.create!(title: "Partir")
      patch reorder_guide_chapters_path, params: { ids: [autre.id, chapitre.id] }, as: :json
      expect(GuideChapter.ordered.to_a).to eq([autre, chapitre])

      patch reorder_pages_guide_chapter_path(autre), params: { ids: [page.id] }, as: :json
      expect(page.reload.chapter).to eq(autre)
    end

    it "ne supprime un chapitre qu'une fois vide, et retire une page sans perdre son historique" do
      delete guide_chapter_path(chapitre)
      expect(GuideChapter.exists?(chapitre.id)).to be(true)

      delete guide_page_path(page)
      expect(GuidePage.exists?(page.id)).to be(false)
      expect(GuidePageRevision.where(guide_page_id: page.id)).to exist

      delete guide_chapter_path(chapitre)
      expect(GuideChapter.exists?(chapitre.id)).to be(false)
    end
  end

  describe "« Voir la procédure » depuis un écran" do
    let(:communication) { User.create!(email: "com@les4sources.be", password: "password123", access_roles: %w[communication]) }

    it "un rédacteur lie l'écran à une page ; tout le monde voit alors le lien" do
      sign_in sourcier
      get events_path
      expect(response.body).to include("Lier une page du Guide à cet écran")
      expect(response.body).not_to include("Voir la procédure")

      get new_guide_screen_link_path(screen: "events#index", path: "/events", label: "Activités")
      expect(response.body).to include("Procédures › Soumettre une note de frais")

      post guide_screen_links_path, params: { screen: "events#index", path: "/events", label: "Activités", guide_page_id: page.id }
      expect(response).to redirect_to("/events")
      expect(GuideScreenLink.sole).to have_attributes(screen: "events#index", page: page, user: sourcier)

      sign_in communication
      get events_path
      expect(response.body).to include("Voir la procédure", guide_page_path(page))
      expect(response.body).not_to include("Lier une page du Guide", "Changer la procédure")

      get guide_page_path(page)
      expect(response.body).to include("S'ouvre depuis les écrans", %(href="/events">Activités</a>))
    end

    it "le formulaire en erreur (create) garde la procédure de son écran (new)" do
      expect(GuideScreenLink.screen_key("events", "create")).to eq("events#new")
      expect(GuideScreenLink.screen_key("finance/expense_reports", "update")).to eq("finance/expense_reports#edit")
    end

    it "est refusé à qui lit seulement le Guide, et ne renvoie jamais hors de Claudy" do
      sign_in communication
      post guide_screen_links_path, params: { screen: "events#index", path: "/events", guide_page_id: page.id }
      expect(GuideScreenLink.count).to eq(0)

      sign_in sourcier
      post guide_screen_links_path, params: { screen: "events#index", path: "//evil.example", guide_page_id: page.id }
      expect(response).to redirect_to(guide_root_path)
    end

    it "se tait quand la page est retirée du Guide, et se retire" do
      link = GuideScreenLink.create!(screen: "events#index", page: page, path: "/events")
      sign_in sourcier
      page.soft_delete!(validate: false)
      get events_path
      expect(response.body).not_to include("Voir la procédure")

      delete guide_screen_link_path(link)
      expect(GuideScreenLink.count).to eq(0)
    end
  end

  describe "liens [[Titre]]" do
    before { sign_in sourcier }

    it "montre les pages qui renvoient ici, et ouvre la création d'une page manquante" do
      accueil = GuidePage.new.tap do |p|
        Guide::SavePage.new(p, user: sourcier).call(guide_chapter_id: chapitre.id, title: "Accueil",
                                                    body: "Voir [[Soumettre une note de frais]] et [[Clés du gîte]].")
      end

      get guide_page_path(page)
      expect(response.body).to include("Pages qui renvoient ici", guide_page_path(accueil))

      get guide_page_path(accueil)
      expect(response.body).to include(%(class="guide-wikilink">Soumettre une note de frais</a>),
                                       new_guide_page_path(title: "Clés du gîte"))

      get new_guide_page_path(title: "Clés du gîte")
      expect(response.body).to include(%(value="Clés du gîte"))
    end
  end
end
