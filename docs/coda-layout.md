# CODA — tables de positions

> Recopiées depuis **Febelfin, « Coded statement of account (CODA) », standard 2.7 (EN), annexe I « The lay-out »**, pages 15 à 30. Le numéro de page est indiqué en regard de chaque table.
>
> Ce fichier existe pour une seule raison : **les positions ne s'écrivent jamais de mémoire.** Une position décalée d'un caractère produit des montants faux qui ont l'air plausibles — le pire mode de panne possible pour de la comptabilité. Quand une position est modifiée dans le code, elle se revérifie ici, et ici se revérifie contre la spécification.
>
> Toutes les positions sont **1-indexées et inclusives**, comme dans la spécification. Les enregistrements font 128 caractères.
>
> Source : https://febelfin.be/media/pages/publicaties/2023/febelfin-standaarden-voor-online-bankieren/5d601609cd-1754302976/standard-coda-2.7-en.pdf

## Enregistrement 0 — en-tête (p. 15-16)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `0` |
| 2-5 | 4 | Zéros |
| 6-11 | 6 | Date de création (JJMMAA) |
| 12-14 | 3 | Numéro d'identification de la banque, ou zéros |
| 15-16 | 2 | Code application = `05` |
| 17 | 1 | `D` si duplicata, sinon blanc |
| 18-24 | 7 | Blanc |
| 25-34 | 10 | Référence du fichier déterminée par la banque, ou blanc |
| 35-60 | 26 | Nom du destinataire |
| 61-71 | 11 | BIC de la banque teneuse du compte |
| 72-82 | 11 | Identification du titulaire belge : `0` + numéro d'entreprise |
| 83 | 1 | Blanc |
| 84-88 | 5 | Code « application séparée » |
| 89-104 | 16 | Blanc ou référence de transaction |
| 105-120 | 16 | Blanc ou référence liée |
| 121-127 | 7 | Blanc |
| 128 | 1 | Code version = `2` |

## Enregistrement 1 — ancien solde (p. 17-18)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `1` |
| 2 | 1 | Structure du compte : `0` belge, `1` étranger, `2` IBAN belge, `3` IBAN étranger |
| 3-5 | 3 | Numéro de séquence de l'extrait papier, ou date julienne, ou zéros |
| 6-42 | 37 | Numéro de compte et code devise |
| 43 | 1 | Signe de l'ancien solde : `0` = crédit, `1` = débit |
| 44-58 | 15 | Ancien solde (12 positions + 3 décimales) |
| 59-64 | 6 | Date de l'ancien solde (JJMMAA) |
| 65-90 | 26 | Nom du titulaire |
| 91-125 | 35 | Description du compte |
| 126-128 | 3 | Numéro de séquence de l'extrait codé, ou zéros. Repart à 001 chaque année |

## Enregistrement 2.1 — mouvement (p. 19-20)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `2` |
| 2 | 1 | Code article = `1` |
| 3-6 | 4 | Numéro de séquence continu (démarre à 0001) |
| 7-10 | 4 | Numéro de détail (démarre à 0000 pour chaque nouvelle séquence) |
| 11-31 | 21 | Référence de la banque (purement informative) |
| 32 | 1 | Signe du mouvement : `0` = crédit, `1` = débit |
| 33-47 | 15 | Montant (12 positions + 3 décimales) |
| 48-53 | 6 | Date valeur (JJMMAA), ou `000000` si inconnue |
| 54-61 | 8 | Code transaction (annexe II) |
| 62 | 1 | Type de communication : `0` = libre ou aucune, `1` = structurée |
| 63-115 | 53 | Zone de communication. Si pos. 62 = `1` : type en 63-65, communication à partir de 66 |
| 116-121 | 6 | Date comptable (JJMMAA) |
| 122-124 | 3 | Numéro de séquence de l'extrait papier |
| 125 | 1 | Code de globalisation |
| 126 | 1 | Code suivant : `1` = un enregistrement 2 ou 3 suit |
| 127 | 1 | Blanc |
| 128 | 1 | Code de lien : `1` = un enregistrement d'information suit |

## Enregistrement 2.2 — mouvement, suite (p. 21-22)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `2` |
| 2 | 1 | Code article = `2` |
| 3-6 | 4 | Numéro de séquence continu |
| 7-10 | 4 | Numéro de détail |
| 11-63 | 53 | Communication (suite) |
| 64-98 | 35 | Référence client, ou blanc |
| 99-109 | 11 | BIC de la banque de la contrepartie, ou blanc |
| 110-112 | 3 | Blanc |
| 113 | 1 | Type de R-transaction : `1` rejet, `2` retour, `3` remboursement, `4` extourne, `5` annulation |
| 114-117 | 4 | Code motif ISO, ou blanc |
| 118-121 | 4 | CategoryPurpose |
| 122-125 | 4 | Purpose |
| 126 | 1 | Code suivant |
| 127 | 1 | Blanc |
| 128 | 1 | Code de lien |

## Enregistrement 2.3 — mouvement, contrepartie (p. 23)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `2` |
| 2 | 1 | Code article = `3` |
| 3-6 | 4 | Numéro de séquence continu |
| 7-10 | 4 | Numéro de détail |
| 11-47 | 37 | Numéro de compte de la contrepartie et code devise, ou blanc |
| 48-82 | 35 | Nom de la contrepartie |
| 83-125 | 43 | Communication (suite) |
| 126 | 1 | Code suivant — toujours `0` |
| 127 | 1 | Blanc |
| 128 | 1 | Code de lien |

## Enregistrement 3.1 — information (p. 24-25)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `3` |
| 2 | 1 | Code article = `1` |
| 3-6 | 4 | Numéro de séquence continu — identique à celui du mouvement concerné |
| 7-10 | 4 | Numéro de détail |
| 11-31 | 21 | Référence de la banque — identique à celle du mouvement concerné |
| 32-39 | 8 | Code transaction |
| 40 | 1 | Structure de la communication : `0` libre, `1` structurée |
| 41-113 | 73 | Communication |
| 114-125 | 12 | Blanc |
| 126 | 1 | Code suivant |
| 127 | 1 | Blanc |
| 128 | 1 | Code de lien |

## Enregistrement 4 — communication libre (p. 29)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `4` |
| 2 | 1 | Blanc |
| 3-6 | 4 | Numéro de séquence continu |
| 7-10 | 4 | Numéro de détail |
| 11-32 | 22 | Blanc |
| 33-112 | 80 | Texte de la communication libre |
| 113-127 | 15 | Blanc |
| 128 | 1 | Code de lien |

## Enregistrement 8 — nouveau solde (p. 28)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `8` |
| 2-4 | 3 | Numéro de séquence de l'extrait papier |
| 5-41 | 37 | Numéro de compte et code devise |
| 42 | 1 | Signe du nouveau solde : `0` = crédit, `1` = débit |
| 43-57 | 15 | Nouveau solde (12 positions + 3 décimales) |
| 58-63 | 6 | Date du nouveau solde (JJMMAA) |
| 64-127 | 64 | Blanc |
| 128 | 1 | Code de lien : `1` = une communication libre suit |

## Enregistrement 9 — fin de fichier (p. 30)

| Positions | Long. | Contenu |
|---|---|---|
| 1 | 1 | Identification = `9` |
| 2-16 | 15 | Blanc |
| 17-22 | 6 | Nombre d'enregistrements 1, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3 et 8 |
| 23-37 | 15 | Total des mouvements débiteurs — somme des montants des enregistrements 2 **de détail 0000** |
| 38-52 | 15 | Total des mouvements créditeurs — même règle |
| 53-127 | 75 | Blanc |
| 128 | 1 | Code multi-fichiers : `1` = un autre fichier suit, `2` = dernier |

## Ce que la spécification impose et qu'on applique

- **Le détail `0000` est le mouvement lui-même** ; les détails `0001` et suivants sont la décomposition d'une transaction globalisée. L'enregistrement 9 ne totalise que les détails `0000` — on crée donc une ligne de trésorerie par enregistrement 2.1 de détail `0000`, et jamais pour ses détails, sous peine de compter deux fois.
- **Les montants portent trois décimales.** En euros, la troisième est toujours nulle. Le parseur refuse un montant dont elle ne l'est pas plutôt que d'arrondir : on n'invente pas un centime sur de l'argent réel.
- **Le signe est du point de vue du titulaire** : `0` = crédit = l'argent entre, `1` = débit = l'argent sort.
