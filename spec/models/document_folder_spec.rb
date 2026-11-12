require "rails_helper"

# Les dossiers des Documents (2026-11-12) : noms uniques parmi les voisins,
# jamais rangés dans eux-mêmes, et la corbeille qui jette et restaure d'un bloc.
RSpec.describe DocumentFolder do
  include ActiveSupport::Testing::TimeHelpers

  let!(:admin) { DocumentFolder.create!(name: "Administratif") }
  let!(:contrats) { DocumentFolder.create!(name: "Contrats", parent: admin) }
  let!(:annee) { DocumentFolder.create!(name: "2026", parent: contrats) }

  def add_file(name, folder)
    DocumentFile.new(name: name, folder: folder).tap do |file|
      file.file.attach(io: StringIO.new("%PDF-1.4"), filename: name, content_type: "application/pdf")
      file.save!
    end
  end

  it "connaît ses ancêtres et tout ce qu'il contient" do
    expect(annee.ancestors).to eq([admin, contrats])
    expect(admin.subtree_ids).to contain_exactly(admin.id, contrats.id, annee.id)
    expect(annee.path_label).to eq("Administratif › Contrats › 2026")
  end

  it "refuse un nom déjà pris à côté, sans casse ni accents, mais pas ailleurs" do
    expect(DocumentFolder.new(name: "CONTRATS", parent: admin)).not_to be_valid
    expect(DocumentFolder.new(name: "Contrats", parent: nil)).to be_valid
    DocumentFolder.create!(name: "Été", parent: admin)
    expect(DocumentFolder.new(name: "ete", parent: admin)).not_to be_valid
  end

  it "propose le premier nom libre" do
    expect(DocumentFolder.available_name("Contrats", admin.id)).to eq("Contrats (2)")
    expect(DocumentFile.available_name("Bail.pdf", contrats.id)).to eq("Bail.pdf")
    add_file("Bail.pdf", contrats)
    expect(DocumentFile.available_name("bail.pdf", contrats.id)).to eq("bail (2).pdf")
  end

  it "ne se range ni dans lui-même ni dans un sous-dossier" do
    admin.parent = annee
    expect(admin).not_to be_valid
    admin.parent = admin
    expect(admin).not_to be_valid
  end

  describe "la corbeille" do
    it "jette un dossier avec tout son contenu, et ne montre que lui dans la corbeille" do
      file = add_file("Bail.pdf", annee)
      trash = Documents::Trash.new
      trash.put(folders: [contrats])

      expect(contrats.reload.deleted_at).to eq(annee.reload.deleted_at)
      expect(file.reload).to be_trashed
      expect(Documents::Trash.top_folders).to eq([contrats])
      expect(Documents::Trash.top_files).to be_empty
    end

    it "restaure un fichier jeté à part dans le premier dossier encore en place" do
      file = add_file("Bail.pdf", annee)
      trash = Documents::Trash.new
      trash.put(files: [file])
      travel 1.second
      trash.put(folders: [contrats.reload])

      expect(Documents::Trash.top_files).to eq([file])
      trash.restore(files: [file.reload])
      expect(file.reload.folder).to eq(admin)
      expect(annee.reload).to be_trashed
    end

    it "numérote un dossier restauré dont le nom a été repris entre-temps" do
      trash = Documents::Trash.new
      trash.put(folders: [contrats])
      DocumentFolder.create!(name: "Contrats", parent: admin)
      trash.restore(folders: [contrats.reload])
      expect(contrats.reload.name).to eq("Contrats (2)")
    end
  end
end
