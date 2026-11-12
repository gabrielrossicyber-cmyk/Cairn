import Foundation

/// Modèles de pages insérés par le menu « / ».
/// ⟦texte⟧ = texte sélectionné après l'insertion (tu tapes directement par-dessus).
enum SlashTemplates {

    private static var today: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    // MARK: /cours

    static func course() -> String {
        """
        ## Module
        ⟦Nom du module⟧ — cours du \(today)

        ## Notions clés
        - 

        ## Explications
        ###


        ## Exemple concret


        ## À retenir
        - [ ] 

        ## Questions d'examen probables
        1. 

        ## Liens
        - Note Notion : 
        - Labs associés : 

        """
    }

    // MARK: /revision (structure : définition, exemple, question)

    static let revision = """
    ## ⟦Notion⟧

    ### 1. Définition


    ### 2. Exemple concret


    ### 3. Question de compréhension
    **Question :** 

    > [!REPONSE]
    > Réponse

    """

    // MARK: /incident (phases NIST SP 800-61)

    static func incident() -> String {
        """
        ## Résumé
        | Champ | Valeur |
        | --- | --- |
        | ID | ⟦INC-001⟧ |
        | Date de détection | \(today) |
        | Sévérité | Critique / Haute / Moyenne / Basse |
        | Statut | Ouvert |
        | Systèmes touchés |  |
        | Détecté par | SOC / EDR / utilisateur |

        ## Chronologie
        | Date / heure | Événement | Source |
        | --- | --- | --- |
        | \(today) 00:00 |  |  |

        ## Détection et analyse
        - Indicateurs de compromission (IoC) : 
        - Technique MITRE ATT&CK : 
        - Cause probable : 

        ## Confinement
        - [ ] 

        ## Éradication
        - [ ] 

        ## Récupération
        - [ ] 

        ## Leçons apprises
        - Ce qui a bien fonctionné : 
        - À améliorer : 
        - Actions de suivi : 

        ## Références
        - Procédure : 
        - Ticket : 

        """
    }

    // MARK: /glossaire

    static let glossary = """
    | Terme | Définition | Exemple | À ne pas confondre avec |
    | --- | --- | --- | --- |
    | ⟦Terme⟧ |  |  |  |

    """

    // MARK: /cve

    static let vulnerability = """
    ## ⟦CVE-AAAA-NNNNN⟧
    | Champ | Valeur |
    | --- | --- |
    | Produit / version |  |
    | Score CVSS |  |
    | Vecteur CVSS |  |
    | Exploitée activement (CISA KEV) | Oui / Non |
    | Correctif disponible | Oui / Non |

    ### Description


    ### Impact


    ### Détection
    ```bash

    ```

    ### Remédiation
    - [ ] 

    ### Références
    - NVD : https://nvd.nist.gov/vuln/detail/

    """

    // MARK: /mitre

    static let mitre = """
    ## ⟦T0000⟧ — Nom de la technique
    | Champ | Valeur |
    | --- | --- |
    | Tactique |  |
    | Plateformes |  |
    | Lien | https://attack.mitre.org/techniques/ |

    ### Fonctionnement


    ### Exemple réel


    ### Détection (SOC)
    - Sources de logs : 
    - Règle / requête : 

    ```

    ```

    ### Mitigation
    - 

    """

    // MARK: /outil

    static let tool = """
    ## ⟦Nom de l'outil⟧
    **Usage :** 

    **Catégorie :** Reconnaissance / Exploitation / Analyse / Défense

    ### Installation
    ```bash

    ```

    ### Commandes essentielles
    | Commande | Effet |
    | --- | --- |
    |  |  |

    ### Exemple
    ```bash

    ```

    ### Pièges et bonnes pratiques
    - 

    """

    // MARK: /procedure

    static let procedure = """
    ## Objectif
    ⟦À quoi sert cette procédure.⟧

    ## Quand l'utiliser


    ## Prérequis
    - [ ] 

    ## Étapes
    1. 

    ## Vérification
    - [ ] 

    ## Retour arrière
    1. 

    ## Contacts / escalade
    - 

    """

    // MARK: Schémas UML / BPMN (rendus par Mermaid)

    static let umlClass = """
    ```mermaid
    classDiagram
        class ⟦Utilisateur⟧ {
            +String nom
            +String email
            +seConnecter()
        }
        class Compte {
            +String identifiant
            +bool mfaActif
            +verrouiller()
        }
        class Role {
            +String nom
            +List permissions
        }
        Utilisateur "1" --> "*" Compte : possède
        Compte "*" --> "*" Role : a
    ```

    """

    static let umlState = """
    ```mermaid
    stateDiagram-v2
        state "Nouveau" as Nouveau
        state "En analyse" as Analyse
        state "Confirmé" as Confirme
        state "Faux positif" as FauxPositif
        state "Résolu" as Resolu
        [*] --> Nouveau
        Nouveau --> Analyse : ⟦alerte reçue⟧
        Analyse --> Confirme : IoC trouvés
        Analyse --> FauxPositif : rien de suspect
        Confirme --> Resolu : remédiation
        FauxPositif --> [*]
        Resolu --> [*]
    ```

    """

    static let umlActivity = """
    ```mermaid
    flowchart TD
        debut((Début)) --> a[⟦Recevoir la demande d'accès⟧]
        a --> d{Manager approuve ?}
        d -- Oui --> b[Créer le compte]
        d -- Non --> c[Refuser la demande]
        b --> e[Informer l'utilisateur]
        c --> e
        e --> fin(((Fin)))
    ```

    """

    static let entityRelation = """
    ```mermaid
    erDiagram
        UTILISATEUR ||--o{ COMPTE : possede
        COMPTE ||--o{ CONNEXION : genere
        COMPTE }o--o{ ROLE : a
        UTILISATEUR {
            string ⟦nom⟧
            string email
        }
        CONNEXION {
            datetime date
            string ip_source
            bool succes
        }
    ```

    """

    /// BPMN simplifié : couloirs = subgraph, événements = cercles, passerelles = losanges.
    static let bpmn = """
    ```mermaid
    flowchart LR
        subgraph U[Utilisateur]
            start((Début)) --> t1[⟦Signaler un incident⟧]
        end
        subgraph S[SOC]
            t1 --> t2[Analyser l'alerte]
            t2 --> g{Incident confirmé ?}
            g -- Non --> fin1(((Clôturé)))
        end
        subgraph R[Équipe réponse]
            g -- Oui --> t3[Contenir]
            t3 --> t4[Éradiquer et restaurer]
            t4 --> fin2(((Fin)))
        end
    ```

    """
}
