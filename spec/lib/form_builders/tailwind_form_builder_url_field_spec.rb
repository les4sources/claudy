require "rails_helper"

# `url_field` n'était pas surchargé : le champ « Vidéo » d'un événement
# sortait sans libellé ni aide, `label:` et `hint:` en attributs HTML.
RSpec.describe FormBuilders::TailwindFormBuilder, type: :helper do
  subject(:html) do
    helper.form_with(model: Event.new, url: "/x", scope: :event,
                     builder: described_class) do |f|
      f.url_field :video_url, label: "Vidéo (lien YouTube)", hint: "Une aide."
    end
  end

  it "rend un champ URL avec son libellé et son aide" do
    expect(html).to include('type="url"')
    expect(html).to include('name="event[video_url]"')
    expect(html).to include("Vidéo (lien YouTube)")
    expect(html).to include("Une aide.")
  end

  it "ne laisse pas fuir label ni hint sur le champ" do
    champ = html[/<input[^>]*type="url"[^>]*>/]
    expect(champ).to be_present
    expect(champ).not_to include("hint=")
    expect(champ).not_to include("label=")
  end
end
