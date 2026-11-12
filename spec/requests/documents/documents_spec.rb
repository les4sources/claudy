require "rails_helper"

# La section Documents (Michael, 2026-11-12) : dossiers, envoi de fichiers,
# renommer, déplacer, corbeille, aperçu. Ouverte aux Sourciers et à
# l'Administratif ; les autres rôles ne la voient pas.
RSpec.describe "Documents", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:sourcier) { User.create!(email: "michael@les4sources.be", password: "password123", access_roles: %w[sourcier]) }
  let(:pdf) { fixture_file_upload(Rails.root.join("spec/fixtures/files/ticket.pdf"), "application/pdf") }
  let(:png) { fixture_file_upload(Rails.root.join("spec/fixtures/files/capture.png"), "image/png") }
  let!(:admin) { DocumentFolder.create!(name: "Administratif") }
  let!(:contrats) { DocumentFolder.create!(name: "Contrats", parent: admin) }

  def html = Nokogiri::HTML(response.body)

  def add_file(name, folder: nil, upload: pdf)
    DocumentFile.new(name: name, folder: folder).tap do |file|
      file.file.attach(upload)
      file.save!
    end
  end

  describe "accès" do
    it "ouvre la section aux Sourciers et à l'Administratif, en écriture" do
      %w[sourcier administratif].each do |role|
        user = User.create!(email: "#{role}@les4sources.be", password: "password123", access_roles: [role])
        sign_in user
        get documents_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Envoyer des fichiers", "Nouveau dossier")
        sign_out user
      end
    end

    it "ferme la section aux autres rôles, et la retire de la navigation" do
      kid = User.create!(email: "kid@les4sources.be", password: "password123", access_roles: %w[kid communication])
      sign_in kid
      get documents_path
      expect(response).to redirect_to(root_path)

      post documents_folders_path, params: { folder: { name: "Pirate" } }
      expect(DocumentFolder.where(name: "Pirate")).to be_empty

      get download_documents_file_path(add_file("Statuts.pdf"))
      expect(response).not_to have_http_status(:ok)

      get root_path
      expect(response.body).not_to include(documents_path)
    end

    it "met l'icône Documents dans les deux barres de navigation" do
      sign_in sourcier
      get documents_path
      expect(html.at_css("nav a[href='#{documents_path}'][title='Documents']")).to be_present

      sourcier.update!(new_interface: true)
      get documents_path
      expect(html.at_css(".ui-side a[href='#{documents_path}']")&.text).to include("Documents")
    end
  end

  context "en Sourcier" do
    before { sign_in sourcier }

    it "montre la racine : l'arbre, les dossiers et les fichiers" do
      add_file("Charte du collectif.pdf")
      get documents_path

      expect(response).to have_http_status(:ok)
      expect(html.at_css("h1").text).to eq("Documents")
      expect(html.css(".ui-docs-tree .ui-docs-node-t").map(&:text)).to include("Administratif")
      expect(html.css(".ui-docs-folder-t").map(&:text)).to eq(["Administratif"])
      expect(html.css(".ui-docs-row-t").map(&:text)).to eq(["Charte du collectif.pdf"])
      # Les menus ⋯ disent au contrôleur ce qu'ils renomment ou déplacent.
      expect(html.css(".ui-docs-row .ui-docs-mi[data-documents-kind-param='file']").size).to eq(3)
      expect(html.css(".ui-docs-folder .ui-docs-mi[data-documents-kind-param='folder']").size).to eq(3)
    end

    it "ouvre un dossier, avec son fil d'Ariane et l'arbre ouvert jusqu'à lui" do
      get documents_folder_path(contrats)

      expect(html.at_css("h1").text).to eq("Contrats")
      expect(html.css(".ui-docs-crumbs a").map(&:text).map(&:strip)).to eq(["Documents", "Administratif"])
      expect(html.at_css(".ui-docs-node[aria-current='page']").text).to include("Contrats")
      expect(response.body).to include("Ce dossier est vide.")
    end

    it "crée un dossier, et numérote un nom déjà pris" do
      post documents_folders_path, params: { folder: { name: "Assurances", parent_id: admin.id } }
      expect(response).to redirect_to(documents_folder_path(admin))
      expect(admin.children.kept.pluck(:name)).to include("Assurances")

      post documents_folders_path, params: { folder: { name: "contrats", parent_id: admin.id } }
      expect(admin.children.kept.pluck(:name)).to include("contrats (2)")
    end

    describe "envoyer des fichiers" do
      it "envoie un formulaire multipart (sinon Turbo jette les fichiers sans rien dire)" do
        get documents_folder_path(contrats)
        form = html.at_css("form:has(input[type=file][name='files[]'])")
        expect(form["enctype"]).to eq("multipart/form-data")
        expect(form["action"]).to eq(documents_files_path)
      end

      it "range plusieurs fichiers dans le dossier, et numérote un doublon de nom" do
        add_file("ticket.pdf", folder: contrats)
        post documents_files_path, params: { folder_id: contrats.id, files: [pdf, png] }

        expect(response).to have_http_status(:see_other)
        expect(contrats.files.kept.pluck(:name)).to contain_exactly("ticket.pdf", "ticket (2).pdf", "capture.png")
        expect(contrats.files.kept.last.uploaded_by).to eq(sourcier)
        expect(flash[:notice]).to eq("2 fichiers envoyés dans « Contrats ».")
      end

      it "répond en JSON au glisser-déposer" do
        post documents_files_path, params: { folder_id: "", files: [pdf] }, headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["created"]).to eq(1)
        expect(DocumentFile.find(body["ids"].first).folder).to be_nil
      end

      it "échappe le nom d'un fichier dans le bandeau, qui rend le HTML tel quel" do
        evil = fixture_file_upload(Rails.root.join("spec/fixtures/files/ticket.pdf"), "application/pdf")
        allow(evil).to receive(:original_filename).and_return("<img src=x onerror=alert(1)>.pdf")
        post documents_files_path, params: { folder_id: contrats.id, files: [evil] }
        follow_redirect!
        expect(response.body).not_to include("<img src=x")
        expect(html.css(".ui-docs-row-t").map(&:text)).to include("<img src=x onerror=alert(1)>.pdf")
      end
    end

    it "renomme un fichier en gardant son extension" do
      file = add_file("scan001.pdf", folder: contrats)
      patch documents_file_path(file), params: { file: { name: "Contrat de bail" } }

      expect(file.reload.name).to eq("Contrat de bail.pdf")
      expect(flash[:notice]).to include("s’appelle maintenant « Contrat de bail.pdf »")
    end

    it "refuse de renommer un dossier comme son voisin" do
      DocumentFolder.create!(name: "Statuts", parent: admin)
      patch documents_folder_path(contrats), params: { folder: { name: "statuts" } }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("existe déjà")
      expect(contrats.reload.name).to eq("Contrats")
    end

    describe "déplacer" do
      it "range une sélection de fichiers et de dossiers dans un autre dossier" do
        file = add_file("Bail.pdf")
        other = DocumentFolder.create!(name: "Archives")
        patch documents_move_path, params: { target_folder_id: other.id, file_ids: [file.id], folder_ids: [admin.id] },
                                   headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["message"]).to eq("2 éléments déplacés dans « Archives ».")
        expect(file.reload.folder).to eq(other)
        expect(admin.reload.parent).to eq(other)
      end

      it "remonte à la racine" do
        patch documents_move_path, params: { target_folder_id: "root", folder_ids: [contrats.id] }
        expect(contrats.reload.parent).to be_nil
      end

      it "refuse de ranger un dossier dans un de ses sous-dossiers, et rien ne bouge" do
        file = add_file("Bail.pdf")
        patch documents_move_path, params: { target_folder_id: contrats.id, folder_ids: [admin.id], file_ids: [file.id] },
                                   headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("sous-dossiers")
        expect(admin.reload.parent).to be_nil
        expect(file.reload.folder).to be_nil
      end
    end

    describe "la corbeille" do
      it "jette un dossier avec son contenu, le restaure d'un bloc" do
        file = add_file("Bail.pdf", folder: contrats)
        post documents_throw_path, params: { folder_ids: [admin.id] }

        expect(DocumentFolder.kept).to be_empty
        expect(file.reload).to be_trashed
        get documents_trash_path
        expect(html.css(".ui-docs-row-t").map(&:text)).to eq(["Administratif"])

        patch documents_restore_path, params: { folder_ids: [admin.id] }
        expect(DocumentFolder.kept.pluck(:name)).to contain_exactly("Administratif", "Contrats")
        expect(file.reload).not_to be_trashed
      end

      it "ne montre plus un dossier jeté, et renvoie vers la corbeille" do
        Documents::Trash.new.put(folders: [contrats])
        get documents_folder_path(contrats)
        expect(response).to redirect_to(documents_trash_path)

        get documents_folder_path(admin)
        expect(html.css(".ui-docs-folder-t")).to be_empty
      end

      it "supprime définitivement, fichier compris" do
        file = add_file("Bail.pdf", folder: contrats)
        Documents::Trash.new.put(folders: [contrats])
        blob_id = file.file.blob.id

        perform_enqueued_jobs do
          delete documents_purge_path, params: { folder_ids: [contrats.id] }
        end

        expect(DocumentFolder.exists?(contrats.id)).to be(false)
        expect(DocumentFile.exists?(file.id)).to be(false)
        expect(ActiveStorage::Blob.exists?(blob_id)).to be(false)
        expect(admin.reload).not_to be_trashed
      end

      it "se vide d'un geste" do
        Documents::Trash.new.put(folders: [admin], files: [add_file("Vieux.pdf")])
        delete documents_purge_path(all: 1)
        expect(DocumentFolder.count + DocumentFile.count).to eq(0)
      end
    end

    describe "aperçu et téléchargement" do
      it "montre le PDF dans la page, servi par Claudy et pas par une adresse publique" do
        file = add_file("Statuts.pdf", folder: contrats)
        get documents_file_path(file)

        expect(response).to have_http_status(:ok)
        iframe = html.at_css("iframe.ui-docs-pdf")
        expect(iframe["src"]).to start_with(raw_documents_file_path(file))
        expect(response.body).not_to include("/rails/active_storage/")

        get raw_documents_file_path(file)
        expect(response.media_type).to eq("application/pdf")
        expect(response.headers["Content-Disposition"]).to start_with("inline")
      end

      it "télécharge sous le nom donné dans Claudy" do
        file = add_file("Statuts signés.pdf")
        get download_documents_file_path(file)

        expect(response).to have_http_status(:ok)
        expect(response.headers["Content-Disposition"]).to start_with("attachment").and include("Statuts%20sign%C3%A9s.pdf")
      end

      it "ne sert jamais en ligne un type qui exécuterait du code" do
        html_file = add_file("page.html", upload: Rack::Test::UploadedFile.new(StringIO.new("<script>alert(1)</script>"), "text/html", original_filename: "page.html"))
        get raw_documents_file_path(html_file)
        expect(response.headers["Content-Disposition"]).to start_with("attachment")
      end

      it "lit un fichier texte dans la page" do
        text = add_file("notes.txt", upload: Rack::Test::UploadedFile.new(StringIO.new("Clé du local : sous le pot"), "text/plain", original_filename: "notes.txt"))
        get documents_file_path(text)
        expect(html.at_css("pre.ui-docs-text").text).to eq("Clé du local : sous le pot")
      end
    end

    it "cherche par nom dans tous les dossiers, sans casse ni accents" do
      add_file("Procès-verbal AG 2026.pdf", folder: contrats)
      add_file("Facture.pdf")
      get documents_path(q: "proces verbal")

      expect(html.css(".ui-docs-row-t").map(&:text)).to eq(["Procès-verbal AG 2026.pdf"])
      expect(html.at_css(".ui-docs-row .ui-row-s").text).to include("Dans Administratif › Contrats")
    end

    it "trouve un document depuis la palette ⌘K" do
      add_file("Statuts coordonnés.pdf", folder: contrats)
      get command_search_path(q: "statuts")
      expect(Nokogiri::HTML(response.body).at_css(".ui-cmd-g[aria-label='Documents']").text).to include("Statuts coordonnés.pdf", "dans Contrats")
    end
  end
end
