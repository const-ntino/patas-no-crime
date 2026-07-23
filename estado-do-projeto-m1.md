# Estado do Projeto — Patas no Crime (handoff pro Claude Code)

Este documento existe pra você (Claude Code) entender rápido tudo que já
foi construído, por quê, e onde continuar — sem precisar redescobrir por
tentativa e erro decisões que já custaram tempo real pra acertar. Leia
isto **uma vez, por completo**, antes de tocar em qualquer código. Depois
disso, o `CLAUDE.md` na raiz do projeto é o que rege o dia a dia (regras
operacionais enxutas, carregadas toda sessão). Este documento aqui não
precisa ser recarregado sempre — é onboarding profundo, não regra viva.

Documentos relacionados, todos em `docs/`: `prd-patas-no-crime.md`
(escopo e marcos), `gdd-completo-patas-no-crime.md` (design completo),
`backlog.md` (ideias fora de escopo e lições técnicas), `devlog-m0.md`
(retrospectiva do M0). Leia-os também — este documento resume e aponta
pra eles, não os substitui.

---

## 1. O que é o projeto

Co-op de furto pra 2-4 jogadores, animais com habilidades assimétricas
invadindo uma casa suburbana. Godot 4.7, GDScript, dev solo em tempo
livre, **usando este projeto explicitamente para aprender multiplayer
no Godot** — isso importa: toda decisão de arquitetura deve vir com
explicação (o que foi escolhido, alternativas, por quê, o que custa),
não só o código funcionando. Isso vale para você também.

## 2. Estado atual dos marcos

**M0 (Fundação): CONCLUÍDO.** Tag `v0.1.0-m0`. Gate confirmado: duas
instâncias (host+cliente) rodando o build exportado pelo CI (não só no
editor), arquitetura host-autoritativa funcionando de ponta a ponta.
Retrospectiva completa em `docs/devlog-m0.md`.

**M1 (MVP jogável): EM ANDAMENTO.** Plano de 11 sessões acordado com o
usuário (ordem: infraestrutura de percepção antes de reação — não
reordenar sem perguntar). Progresso:

| # | Sessão | Status |
|---|---|---|
| 1 | Portas/janelas manipuláveis (Manipular) + Voo (Voar) | concluída |
| 2 | Objetos e carga (Leve/Médio/Pesado/Fixo-arrastável, RF-05) | concluída |
| — | Correção de câmera (fora do plano original, ver seção 6) | concluída |
| 3 | Rotina do humano (GDD 5.3, RF-02 parte 1) | concluída |
| 4 | Scouting e marcação (GDD 5.2, RF-02 parte 2, HUD 8.1 parcial) | concluída |
| 5 | Estados de alerta (GDD 5.4, RF-03) | concluída |
| 6 | Ruído (GDD 5.5) | próxima |
| 7 | Chamar do pássaro (GDD 3.2, RF-09) | não iniciada |
| 8 | Pets (GDD 5.6) | não iniciada |
| 9 | Captura e resgate (GDD 5.7, RF-04) | não iniciada |
| 10 | Os 3 objetivos da fase MVP (GDD 6.3) — revisitar proporções do greybox aqui | não iniciada |
| 11 | Vitória, derrota, pontuação, HUD (RF-07, GDD 7.1, HUD 8.1 completo) | não iniciada |

Gate de saída do M1: **G1** (PRD seção 8) — 3 sessões de playtest,
riso não roteirizado em pelo menos 2, conclusão entre 40-70%.

## 3. O que muda com você no lugar do chat

Nas sessões anteriores (via chat), eu não tinha acesso ao disco do
usuário — todo código era entregue como arquivo pra ele copiar
manualmente, testar no editor, e relatar o resultado de volta em texto
(às vezes com screenshot). Isso gerou um ciclo lento e frágil,
especialmente pra depuração de multiplayer.

**Você tem acesso direto.** Edite `.gd`/`.tscn` no lugar, rode `git`,
rode `godot --headless` pra validar export ou rodar scripts. Isso
elimina a maior fonte de atrito das sessões anteriores.

**Desde a sessão 3 do M1, o Godot 4.7 headless está instalado de
verdade no WSL** (`~/.local/bin/godot`, mesma versão do CI). Isso
permite escrever um script `extends SceneTree` descartável, carregar
uma cena, avançar frames de física manualmente
(`await get_tree().physics_frame`) e inspecionar `NavigationServer3D`,
posições, estados etc. direto — muito mais rápido que pedir pro
usuário testar e relatar pra cada hipótese de bug. Use isso
proativamente pra depurar lógica/estado antes de pedir teste ao vivo;
o que continua exigindo o humano é só o que só existe na GUI do editor
(ver próximo parágrafo).

**O que continua exigindo o humano:** qualquer ação que só existe na
interface gráfica do editor Godot — criar autoload pela tela de
Configurações, adicionar propriedades na aba Replicação de um
`MultiplayerSynchronizer`, configurar Input Map, arrastar nós no
painel Cena, ajustar Auto Spawn List de um `MultiplayerSpawner`. Editar
esses campos à mão direto no arquivo de texto é fonte de erro sutil
(ver seção 5). Prefira sempre instruir o usuário a fazer esses passos
pela UI, com o caminho exato de cliques, e confirme o resultado antes
de seguir.

## 4. Arquitetura (resumo — detalhe completo no CLAUDE.md)

- **Host-autoritativo** com a API high-level do Godot desde o
  primeiro commit. `NetworkManager` (autoload) cria servidor ENet se
  `--server` estiver nos argumentos de linha de comando, senão cria
  cliente conectando em `127.0.0.1:8910`.
- **Separação estrita input -> intenção -> simulação.** Só dois
  scripts no projeto inteiro têm permissão de ler `Input.*`:
  `scripts/characters/player_input.gd` e
  `scripts/characters/camera_rig.gd`. Qualquer outro lugar lendo Input
  diretamente é bug de arquitetura.
- **Autoridade dividida dentro do mesmo personagem:** o corpo
  (`CharacterBody3D`, raiz de `character.tscn`) é sempre autoridade do
  host (peer 1) — é o host quem simula todo mundo. `PlayerInput` e
  `CameraRig`, dentro da mesma cena, têm autoridade do peer dono. Essa
  fiação é feita no spawn, em `game_manager.gd`
  (`set_multiplayer_authority`), idêntica em todos os peers.
- **Sincronização contínua via `MultiplayerSynchronizer`** a ~15 Hz
  (`TransformSync` para posição, `FacingSync` para rotação lógica,
  `InputSync` para a intenção do `PlayerInput`). Eventos discretos via
  `@rpc` (porta abrir/fechar, item pegar/soltar) — nunca sincronizados
  como estado contínuo.
- **Câmera 100% local**, nunca participa da rede. Detalhe importante
  (ver seção 6): a câmera é `top_level = true`, desacoplada
  fisicamente da interpolação visual do personagem, com amortecimento
  exponencial próprio.
- **Sem predição client-side.** Risco aceito e documentado (ver
  `docs/backlog.md`), a resolver em M2 com latência real.

## 5. Lições técnicas que já custaram tempo real (não repetir)

Estas vieram de bugs de verdade, cada um levou várias mensagens de
depuração pra isolar. Consulte antes de implementar algo parecido.

**a) Toda variável nova em `PlayerInput` que o host precisa enxergar
tem que ser adicionada manualmente à lista de Replicação do
`InputSync`, na aba própria do editor** (não basta declarar `@export`
no script). Esquecer isso não gera erro — o valor fica silenciosamente
`0`/`false` no host. Aconteceu duas vezes (`vertical_direction`,
depois `is_dragging`).

**b) Todo spawn inicial de qualquer sistema deve rodar via
`.call_deferred()`, nunca direto no corpo de `_ready()`.** O `_ready()`
de nós irmãos roda na ordem em que aparecem na árvore de cena. Um
`GameManager` que tenta usar um `MultiplayerSpawner` que vem depois
dele na árvore falha ou — pior — "funciona" parcialmente: o host cria
o nó localmente (`add_child` funciona sem o spawner), mas o spawner
nunca chega a rastrear aquele nó a tempo, então nunca replica pro
cliente, sem erro nenhum. Isso consumiu uma sessão inteira de
depuração (itens apareciam só no host). A correção: uma função
`_server_start()` chamada como `_server_start.call_deferred()` dentro
do `_ready()`, garantindo que toda a cena terminou de inicializar antes
de qualquer spawn.

**c) `MultiplayerSpawner.spawn_function` com `Dictionary` de dados
customizados provou ser instável no Godot 4.7** (erro recorrente
`Cannot find spawn node`, mesmo com tudo aparentemente configurado
certo). Pro spawn de itens, o padrão que funcionou de forma confiável
foi abandonar `spawn_function` inteiramente: o item nasce via
`add_child()` direto no nó que o Spawn Path do spawner observa, com a
cena registrada na Auto Spawn List. Pro spawn de personagens,
`spawn_function` + `spawner.spawn(peer_id)` (um `int` simples, não um
Dictionary) continua funcionando normalmente — a instabilidade parece
específica a payloads complexos.

**d) RPC de um peer chamando a si mesmo precisa de `"call_local"` na
anotação, não só `"any_peer"`.** Sem isso: `RPC '...' on yourself is
not allowed by selected mode`. Acontece sempre que o host interage com
um objeto que ele mesmo processa (ex.: host abrindo uma porta).

**e) Grupo `"interactable"` vive no nó raiz da cena interagível (ex.:
`Door`, `Item`), não na `Area3D` de detecção dentro dela.** O código de
interação (`player_input.gd`) verifica
`area.get_parent().is_in_group("interactable")` — comparar direto a
área falha silenciosamente (sem erro, só nunca interage).

**f) Geometria com rotação calculada manualmente (matriz `Transform3D`
na mão) é frágil e não vale o risco quando não dá pra testar ao vivo
antes de entregar** (por exemplo, gerando `.tscn` como texto). Custou
três iterações fracassadas construindo uma rampa de escada. Prefira:
(1) usar `rotation_degrees` em vez de montar a matriz de rotação à
mão — o Godot calcula a trigonometria por você; (2) quando a peça
tiver colisão crítica e puder evitar rotação, prefira peças
empilhadas sem rotação nenhuma (funcionou bem para a escada final: 16
degraus retos, cada um sólido do chão até seu próprio topo).

**g) Escala do personagem precisa ser calibrada antes de construir
qualquer greybox novo**, não depois. Pulamos esse passo ao gerar a
Casa da Rua 7 direto de arquivo, e o sintoma (câmera esmagada em
cômodos pequenos) só apareceu com a casa inteira já pronta, exigindo
recalibração tardia da cápsula (raio ~0.25, altura ~0.9) em vez da
casa.

**h) A câmera nunca deve ser filha de um nó que sofre interpolação de
rede (chase-lerp).** Isso fazia a tela inteira pulsar no cliente,
porque a perseguição de posição tem velocidade desigual por natureza.
Corrigido tornando `CameraRig` `top_level = true`, seguindo o corpo
lógico por conta própria com amortecimento exponencial
(`1.0 - exp(-k*delta)`, nunca `lerp` com peso fixo — este último dá
resultado diferente por framerate).

**i) Camadas de colisão: personagem na camada 2, cenário na camada 1.**
O braço da câmera (`SpringArm3D`) tem Collision Mask só na camada 1 —
sem essa separação, a câmera colide com o próprio personagem e
colapsa pra dentro dele.

**j) Rotação da malha visual, não do corpo lógico.** Girar o
`CharacterBody3D` inteiro pra encarar a direção do movimento quebra a
câmera (que é filha dele) — ela giraria junto. A rotação de "encarar"
vive num nó separado (`FacingSync`, replicado) e só o
`MeshInstance3D` (dentro de `VisualRoot`) de fato gira visualmente.

**k) `groups = [...]` num `.tscn` é atributo do CABEÇALHO `[node ...]`,
não uma propriedade solta na linha de baixo.** Escrever
`[node name="X" ...]` seguido de `groups = ["y"]` numa linha própria é
sintaticamente válido mas silenciosamente ignorado — o grupo nunca é
aplicado, sem erro nenhum. Formato correto:
`[node name="X" ... groups=["y"]]`, tudo dentro do mesmo colchete.
Descoberto porque uma `NavigationMesh` configurada com
`SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN` assava consistentemente 0
vértices — o grupo-fonte estava sempre vazio.

**l) `NavigationRegion3D.bake_navigation_mesh()` chamado cedo demais
(1 frame via `call_deferred`) produz uma malha com vértices "corretos"
na aparência (contagem e coordenadas plausíveis) mas que falha
silenciosamente em toda consulta subsequente (`map_get_path`,
`map_get_closest_point` sempre retornam o zero/origem).** A região
precisa de vários frames de física depois de entrar na árvore antes de
assar — na prática, 10 frames (`for i in 10: await
get_tree().physics_frame`) resolveu de forma reprodutível neste
projeto. Só descoberto instrumentando `NavigationServer3D` direto via
`godot --headless --script` (ver seção 11).

**m) Perseguir um `NavigationAgent3D.get_next_path_position()`
recalculando a direção a cada frame (zerando velocidade quando "chega"
no XZ do alvo) trava ou oscila sempre que o próximo ponto do caminho
tem uma diferença vertical grande** (rampa/escada) — a checagem interna
do agente usa distância 3D, então "cheguei" no plano horizontal nunca
satisfaz "cheguei" de verdade, e zerar a velocidade aí impede o
personagem de continuar empurrando pra dentro da rampa (que é o que
faz `move_and_slide` subir o degrau, via colisão). Correção: travar a
direção de movimento por CORNER (só recalcular quando
`get_next_path_position()` mudar de valor, nunca por proximidade),
imitando um jogador que segura a tecla até atravessar em vez de soltar
assim que "chega" no X/Z.

**n) Colisão invisível estreita + malha de navegação grossa (`cell_size`
grande) fazem o personagem sair do footprint físico de uma rampa
estreita, ou prender numa quina de obstáculo (corrimão) que uma malha
mais fina contornaria.** Alargar a colisão da rampa e reduzir
`cell_size`/`cell_height` (0.25 → 0.1, alinhado ao padrão do mapa de
navegação em `project.godot`, seção `[navigation]`, pra sumir o aviso
de descompasso) resolveu os dois casos na escada da Casa da Rua 7.

**o) Um alvo marcável cuja própria colisão está na camada "cenário"
pode se auto-obstruir num raycast de linha de visão até a própria
origem.** A `Leaf` de `Door` (folha da porta/janela) tem colisão na
camada 1 — a mesma usada pra bloquear linha de visão através de
paredes. Mirar o raycast exatamente na origem do nó `Door` faz a
própria folha bloquear o raio antes de chegar lá. Correção: um deslocamento de mira
configurável (`Markable.sight_offset`) apontando pra um ponto que não
está dentro da geometria sólida do próprio alvo (no caso da porta, acima
da folha, no vão). Vale genericamente pra qualquer alvo marcável cuja
colisão real não seja um ponto (portas, mas potencialmente também
itens grandes no futuro).

## 6. Sobre a correção de câmera (fora do plano original)

Depois da sessão 2 do M1, o usuário reportou que a câmera do cliente
"pulsava" de forma incômoda. Diagnóstico: a câmera era filha de
`VisualRoot`, que faz lerp/chase da posição de rede em degraus de
~66ms — herdando cada pulso. Corrigido com `top_level = true` +
amortecimento exponencial independente (ver item h acima). Isso
resolveu o sintoma mais grave (tela pulsando), mas não elimina
totalmente o micro-passo residual do personagem nem o atraso de
resposta ao próprio input — ambos continuam registrados em
`docs/backlog.md` como escopo de M2 (predição client-side +
interpolação com buffer de timestamp).

## 7. Inventário de arquivos (o que existe e faz o quê)

```
scripts/
  characters/
    character_stats.gd     Resource: stats + capacidades por animal
                            (move_speed, sneak_speed_multiplier,
                            can_manipulate, can_fly, can_drag,
                            max_carry_class)
    character_body.gd       CharacterBody3D: movimento, voo, furtivo,
                            efeito de carga/arrasto na velocidade
    player_input.gd         Único leitor de Input.* (com camera_rig.gd).
                            Compõe direção relativa à câmera, dispara
                            interação (E)
    camera_rig.gd            Câmera 3ª pessoa, top_level, amortecida,
                            controle de mouse (sinais calibrados —
                            não alterar sem retestar)
    visual_interpolation.gd  VisualRoot: suaviza posição/rotação pra
                            quem não é autoridade
    human_npc.gd             CharacterBody3D do humano NPC: rotina
                            WAITING/WALKING via NavigationAgent3D,
                            espera 20-60s seedada em cada ponto (GDD 5.3)

  interactables/
    door.gd                  Porta/janela: interact(), RPC toggle,
                            bloqueada por item Pesado
    item.gd                  Item: RigidBody3D, classes
                            (Leve/Médio/Pesado/Fixo-arrastável),
                            pickup/drop/drag via RPC

  networking/
    network_manager.gd       (autoload) cria servidor ou cliente ENet
    game_manager.gd           Spawna personagens e itens, fixa
                            autoridade, tudo via call_deferred

  debug_overlay.gd            HUD de debug: HOST/CLIENTE + peer id

scenes/
  characters/character.tscn   Ver estrutura completa abaixo
  characters/human_npc.tscn   CharacterBody3D + NavigationAgent3D +
                              TransformSync (mesmo padrão de replicação
                              do personagem jogável) + VisualRoot
  interactables/door.tscn, item.tscn
  greybox/
    casa_rua_7.tscn            Fase MVP (GDD 6.2). Cor por andar:
                              amarelo=térreo/exterior, azul=andar
                              superior, verde=escada. Escada fica na
                              SALA, não no Hall (não cabia na
                              profundidade do Hall — decisão
                              registrada no backlog). Tem
                              NavigationRegion3D (malha assada em
                              runtime pelo GameManager a partir da
                              colisão, grupo "nav_source" em
                              TerreoEstrutura/AndarSuperiorEstrutura/
                              Escada) e Humans/HumanSpawner (mesmo
                              padrão de Items/ItemSpawner)
    session1_test.tscn, teste_verbos.tscn   Cenas de teste descartáveis
  ui/debug_overlay.tscn
  autoloads/ (NetworkManager registrado em Configurações do Projeto)

resources/characters/raccoon_stats.tres, bird_stats.tres

docs/prd-patas-no-crime.md, gdd-completo-patas-no-crime.md,
     backlog.md, devlog-m0.md

.github/workflows/godot-export.yml   CI: export headless Win/Linux por tag
```

Estrutura de `character.tscn`:
```
Character (CharacterBody3D — autoridade sempre do host)
├── CollisionShape3D          (camada de colisão 2)
├── InteractionArea (Area3D)   detecção de interagíveis (mask camada 3)
├── PlayerInput
│   └── InputSync              replica: move_direction, is_sneaking,
│                              vertical_direction, is_dragging
├── TransformSync               replica: position (Character)
├── FacingSync                  replica: rotation (lógica, não visual)
├── HoldPoint                   onde itens carregados se encaixam
└── VisualRoot                  interpola posição (visual_interpolation.gd)
    ├── MeshInstance3D          gira pra encarar direção (FacingSync)
    └── CameraRig                top_level=true, NÃO herda interpolação
        └── CameraPitch
            └── SpringArm3D (colisão só camada 1)
                └── Camera3D
```

## 8. Como testar (multiplayer local)

Duas instâncias na mesma máquina. Se estiver rodando pelo editor:
Depuração -> Executar Instâncias, uma com argumento `--server` (via
"Substituir Argumentos de Execução Principais" naquela linha), outra
sem argumento nenhum. Se estiver validando o build exportado pelo CI:
dois terminais, `patas-no-crime.exe --server` num, e
`patas-no-crime.exe` sozinho no outro.

O overlay de debug (canto superior esquerdo) mostra HOST/CLIENTE e o
peer id de cada janela — use isso pra confirmar qual é qual antes de
testar qualquer coisa.

Prova de autoridade que sempre deve valer: fechar a janela host derruba
a conexão do cliente. Se isso parar de acontecer, algo regrediu na
arquitetura.

## 9. Como trabalhar com o usuário

Ele não é desenvolvedor experiente em Godot/multiplayer — está
aprendendo através deste projeto de propósito. Implicações:

- Toda decisão de arquitetura não trivial merece explicação curta: o
  que foi escolhido, que alternativas existiam, por que esta, o que
  ela custa. Não é aula genérica — é a decisão específica deste
  projeto.
- Tarefa não trivial: plano curto primeiro, esperar confirmação, só
  depois implementar (regra explícita do CLAUDE.md).
- Ele testa manualmente no editor Godot no Windows. Toda entrega
  deveria vir com critério claro de "como eu testo isso com duas
  instâncias".
- Ideias fora do escopo do marco atual: registrar em
  `docs/backlog.md`, seguir em frente — nunca implementar sem
  perguntar primeiro (esquilo, gato, ping contextual, multiplayer
  online são explicitamente fora de escopo até M2/M3/M5).
- Se um teste falhar, é mais produtivo pedir o texto exato do erro
  (aba "Erros" do Depurador, ou console) do que assumir a causa —
  neste projeto, várias vezes o sintoma relatado e a causa real
  estavam em camadas bem diferentes (ver seção 5).

## 10. Próximo passo concreto

Sessão 6 do M1: Ruído (GDD 5.5) — três raios de emissão (passos
correndo, objeto Pesado em movimento, objeto derrubado/colisão),
disparando Desconfiado no ponto de origem. É o gatilho de Desconfiado
que a sessão 5 deixou de fora por não existir nenhum evento de ruído
no projeto ainda — `HumanNPC._enter_desconfiado(ponto)` já existe e
está pronto pra ser chamado por um evento de ruído, não precisa mudar
nada na máquina de estados em si, só emitir o evento.

HUD 8.1 segue parcial: sem timer de partida nem ícones dos 3
objetivos cinza→colorido (dependem de vitória/derrota da sessão 11 e
dos objetivos formais da sessão 10). Ícone de estado (?/!) já entrou
na sessão 5.

## 11. Configuração de autonomia (`.claude/settings.json`)

O projeto tem um `.claude/settings.json` na raiz configurando
`defaultMode: "plan"` — toda sessão começa em Plan Mode (você lê,
propõe um plano, o usuário aprova uma vez, você executa a sessão
inteira sem re-confirmar arquivo por arquivo). Comandos de `git` e
`godot --headless` estão pré-aprovados na lista `allow`, pra não
interromper por esses.

**Isso elimina interrupção de permissão, não elimina pausa de GUI.**
Ações que só existem dentro da janela do editor Godot (autoload,
Input Map, aba Replicação de um Synchronizer, Auto Spawn List de um
Spawner, arrastar nó no painel Cena) continuam exigindo que você pare
e peça pro usuário fazer, com o caminho exato de cliques — nenhuma
configuração de permissão resolve isso, é limitação de categoria
(ferramenta de terminal não controla outra janela). Trate essas pausas
como parte normal do fluxo, não como falha do modo autônomo.
