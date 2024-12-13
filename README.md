# JRES 2024

Lightning Talk aux JRES 2024 à Rennes.

## Informations générales
 - Titre : Migration VMware vers... VMware (vCF)
 - Format : Lightning talk
 - Thème : Type Lightning talk
 - Mots clés : vmware, script, powershell, api, vcenter

## Description

A l'heure où la tendance est à la sortie de solutions VMware, nous avons migrés l'année dernière notre infrastructure VMware classique vers la solution vCloud Foundation (vCF) de VMware.  
Lors de cette migration, nous avons du transférer l'ensemble des VM vers la nouvelle infrastructure vCF.  
Avec ce Lightning Talks, je souhaite présenter le cheminement qui m'a menée au développement d'un script afin d'automatiser la migration de VM entre vCenter.  
Le script utilise les API de VMware avec PowerCLI en PowerShell.

## Plan :
1. Problématique : Migration vers vCF, pas de brownfield
2. Possibilités de migrations existantes : Manuelles et sujettes à des erreurs
3. Le script, il fait quoi en gros ?
4. C'est pas si simple : les difficultés rencontrées
5. Conclusion

## Script

### Slide 1 : Titre

Bonjour à toustes, je suis Julia Leblond, administratrice infrastructure chez Renater.
Je m'occupe notamment de la plateforme virtuelle d'hébergement des service Renater.
Cette plateforme justement, elle était basée sur une infrastructure VMware vSphère classique, et nous l'avons dernièrement migrés vers VMware Cloud Foundation.

### Slide 2 : Pourquoi ?

Alors vCloud Foundation, vCF, c'est un produit miracle vendu par VMware, ça fait papa maman, ... Bon, j'ai quelques petits trucs à y dire quand même !
vCF c'est du déploiement d'infrastructure en propre, il n'y a pas de brownfield, pas d'import d'infrastructure existante, donc ça déploie une nouvelle infra toute neuve, des nouveau vCenter, tout beau, tout propre, tout neuf ...
Et notre ancienne infra, eh bien elle est toujours là, et tout ce qu'il y à dessus, il faut le migrer vers ces nouveau vCenter.

### Slide 3 : Migration entre vCenter

Bon la migration entre vCenter, c'est quelque chose qui existe déjà. On peut le faire à chaud, avec du storage vMotion par l'option d'import de VM depuis un autre vCenter.
On peut également le faire à froid, lorsque les datastore sont présents des deux côtés, on désenregistre la VM d'un côté et on la réenregistre de l'autre côté.
L'avantage c'est qu'il n'y a pas de migration du stockage, c'est ce qui prends du temps. L'inconvénient c'est qu'il y a un downtime puisque ça ne peut se faire qu'à froid.

Mais est-ce qu’on ne pourrait pas le faire à chaud, et sans Storage vMotion ? Eh bien oui c'est possible, via la première méthode et toujours lorsque les datastore sont présent des 2 cotés. En sélectionnant les datastore de destination pour chaque disque identique à la source, il n’y a pas de migration de stockage et la migration de la VM se fait instantanément.
C’est bien beau mais lorsque vous avez plusieurs centaines de VM, que chaque VM à plusieurs disques, des gros disques en plus, et tous sur des datastore différents, ça deviens vite pénible de cliquer sur l’interface pour sélectionner les datastore et en plus vous pouvez faire des erreurs.
Alors on ne pourrait pas le scripter ?

### Slide 4 : Un script !

### Slide 5 : C’est pas si simple

### Slide 6 : On l’a fait ! (Conclusion)
