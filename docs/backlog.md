# Backlog

Ideias e observações fora do escopo do marco atual, registradas conforme
surgem. Nada aqui entra em discussão de implementação até o marco
correspondente chegar — ver docs/prd-patas-no-crime.md seção 8 pros marcos.

---

## Interpolação de rede sem buffer de timestamp (M2)

Sessão 4 (M0): com o tick de sincronização em ~15 Hz, dois sintomas
da mesma causa raiz apareceram, em momentos diferentes:

1. A câmera do próprio jogador cliente ganhou atraso perceptível
   entre apertar tecla e o personagem responder, porque não existe
   predição local — a posição sempre vem confirmada pelo host.
2. Mesmo suavizando com lerp (`visual_interpolation.gd`), sobra uma
   pequena "travadinha" rítmica no movimento de qualquer personagem
   visto por um cliente — o lerp persegue a posição mais recente em
   vez de interpolar *entre* duas posições com timestamp, então toda
   vez que um pacote novo chega (a cada ~66 ms) há uma pequena
   correção de rota visível. Ajustar a velocidade do lerp não resolve
   isso, só muda a rapidez da correção.

Em localhost os dois são pouco perceptíveis (testado a 120 FPS, sem
gargalo de CPU); com latência real de M2, tendem a piorar.

Mitigação para os dois, no mesmo pacote de trabalho de M2: (a)
predição client-side da locomoção do próprio personagem (já registrada
no PRD seção 10), e (b) trocar o lerp "persegue-o-mais-recente" por
interpolação de buffer com timestamp (guardar duas posições recebidas
e interpolar entre elas, não em direção à última). Nenhum dos dois
exige reescrita de arquitetura — a separação input → intenção →
simulação (RT-05) já suporta ambos sem tocar no host. Reavaliar quando
M2 tiver latência de rede real pra testar contra, não antes.

## Vão da escada como esconderijo (M1)

O poço aberto sob a escada da Sala (greybox M0) é um espaço morto que
serve naturalmente como esconderijo marcável (GDD 5.2). Considerar
formalizar como um dos pontos de esconderijo da fase MVP quando a
seção 5.2 do GDD entrar em M1.

## Redesenho do posicionamento da escada (M1+)

A escada do greybox do M0 ficou na Sala (não no Hall, como a primeira
tentativa) por necessidade prática: subir 2,9 m de pé-direito exige
mais percurso horizontal do que o Hall (3 m de profundidade) comporta
numa inclinação caminhável sem mecânica de escalada. Quando o level
design de verdade entrar (M1), vale revisitar se a posição final quer
ficar na Sala mesmo ou se o Hall deveria crescer para acomodar a
escada original, com impacto no restante da planta térrea.

## Técnica de escada: degraus visuais + rampa de colisão fantasma

Registrar como padrão técnico reutilizável: para escadas caminháveis
por CharacterBody3D sem lógica de step-climbing customizada, funciona
melhor ter os degraus como geometria puramente visual
(use_collision = false) e uma rampa lisa separada, invisível
(material transparente), fazendo a colisão de verdade. Evita o
personagem "pular" degrau a degrau. Risco conhecido: se os degraus
visuais forem movidos sem mover a rampa junto, os dois dessincronizam.
Considerar, em algum marco futuro, um script que gere a rampa de
colisão automaticamente a partir da geometria dos degraus.

## Ferramenta de debug: cores por camada/sistema

Colorir geometria do greybox por função (térreo/andar/conector) via
material simples ajudou bastante a diagnosticar problemas de
navegação na sessão 5. Vale considerar formalizar como convenção de
greybox permanente (não só um recurso emergencial), ou até um plugin
simples de editor que aplica isso automaticamente por altura.
