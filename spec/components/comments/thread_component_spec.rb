require "rails_helper"

# Epic #242, phase 1 — le composant du fil, celui qui sera rendu partout.
RSpec.describe Comments::ThreadComponent, type: :component do
  let(:user) { User.create!(email: "michael@les4sources.be", password: "password123") }
  let(:other) do
    User.create!(email: "stephanie@les4sources.be", password: "password123",
                 human: Human.create!(name: "Stéphanie"))
  end
  let(:gathering) do
    Gathering.create!(name: "Réunion du collectif",
                      gathering_category: GatheringCategory.create!(name: "Collectif", color: "emerald"),
                      starts_at: Time.current, ends_at: 1.hour.from_now)
  end

  def comment_by(author, body)
    Comment.create!(commentable: gathering, author: author, body: body)
  end

  it "annonce un fil vide et propose quand même d'écrire" do
    render_inline(described_class.new(commentable: gathering, current_user: user))

    expect(page).to have_text("Aucun commentaire pour l'instant")
    expect(page).to have_css("form[action='/comments']")
    expect(page).to have_button("Commenter")
  end

  it "porte l'identifiant DOM que le Turbo Stream vient remplacer" do
    render_inline(described_class.new(commentable: gathering, current_user: user))

    expect(page).to have_css("##{Comment.thread_dom_id(gathering)}")
  end

  it "rend les commentaires dans l'ordre, avec leur auteur" do
    comment_by(other, "Il manque le ticket du 12/08.")
    comment_by(user, "Je le scanne ce soir.")

    render_inline(described_class.new(commentable: gathering, current_user: user))

    expect(page).to have_text("Stéphanie")
    expect(page).to have_text("Il manque le ticket du 12/08.")
    expect(page).to have_text("Je le scanne ce soir.")
    expect(page.text.index("ticket")).to be < page.text.index("scanne")
  end

  it "porte le nombre de commentaires dans son en-tête" do
    2.times { |i| comment_by(user, "message #{i}") }

    render_inline(described_class.new(commentable: gathering, current_user: user))

    expect(page).to have_css("h2", text: "Commentaires (2)")
  end

  it "n'offre les actions que sur ses propres commentaires" do
    mine = comment_by(other, "à moi")   # `other` est un porteur, pas un admin global
    comment_by(user, "au voisin")

    render_inline(described_class.new(commentable: gathering, current_user: other))

    within = page.find("#comment_#{mine.id}")
    expect(within).to have_button("Modifier")
    expect(page).to have_css("button", text: "Modifier", count: 1)
  end

  it "embarque le formulaire d'édition, masqué, plutôt qu'un aller-retour serveur" do
    comment = comment_by(user, "à moi")

    render_inline(described_class.new(commentable: gathering, current_user: user))

    expect(page).to have_css("#comment_#{comment.id}[data-controller='comment-editor']")
    expect(page).to have_css("[data-comment-editor-target='form'][hidden]", visible: :all)
  end

  it "affiche les erreurs du brouillon quand une soumission a échoué" do
    draft = Comment.new(commentable: gathering, author: user)
    draft.valid?

    render_inline(described_class.new(commentable: gathering, current_user: user, comment: draft))

    expect(page).to have_text("ne peut pas être vide")
  end

  it "ne propose pas d'écrire sans session" do
    render_inline(described_class.new(commentable: gathering, current_user: nil))

    expect(page).not_to have_button("Commenter")
  end
end
