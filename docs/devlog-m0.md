# Devlog — Fim do M0 (Fundação)

**Marco:** M0
**Status:** gate concluído (ver checklist em docs/ ou histórico de sessão)

## O que foi construído

Arquitetura multiplayer host-autoritativa funcionando de ponta a ponta
em LAN local (duas instâncias, host + cliente): input vira intenção no
cliente, sobe por MultiplayerSynchronizer, o host simula todos os
corpos, transforms descem a ~15 Hz com interpolação visual escondendo
o degrau da rede. Câmera em terceira pessoa por jogador, 100% local,
nunca trafega pela rede. Dois personagens (guaxinim, pássaro)
diferenciados por Resource de stats. Greybox completo da Casa da Rua 7
(GDD 6.2), navegável nos dois andares. CI exportando build headless
Windows/Linux por tag.

## O que não saiu como o plano original previa

O plano de 7 sessões assumia que geometria de greybox seria
majoritariamente mecânica (posicionar blocos a partir de uma tabela de
coordenadas). Na prática, a sessão 5 (greybox) consumiu bem mais
iteração do que as outras por dois motivos:

1. **Rotação de geometria calculada à mão é frágil.** A primeira
   tentativa de escada (rampa única rotacionada) errou o cálculo de
   alcance por três vezes seguidas antes de eu abandonar a abordagem
   em favor de degraus retos sem rotação nenhuma — mais peças, mas
   cada uma trivial de verificar. Lição pro resto do projeto: preferir
   geometria sem rotação quando a colisão importa, especialmente em
   qualquer construção feita fora do editor (sem poder testar ao
   vivo antes de entregar).

2. **Escala do personagem não foi calibrada antes de construir a
   casa**, apesar do plano original prever isso explicitamente ("métrica
   de escala travada antes do primeiro cubo"). O passo foi pulado, e o
   sintoma (câmera esmagada em cômodos pequenos) só apareceu depois da
   casa inteira já construída, exigindo recalibração tardia do
   personagem em vez da casa. Confirma por que aquele passo existia.

## Decisões de arquitetura que se mantiveram sem revisão

Host-autoritativo com API high-level desde o commit 1, separação
input → intenção → simulação, câmera local sem participar da rede —
nenhuma dessas exigiu ajuste depois de definidas nas primeiras sessões.
O ponto que mais aproximou de precisar de trabalho extra foi o atraso
perceptível na câmera do próprio jogador causado pelo tick de 15 Hz
sem predição — não corrigido agora, registrado em backlog para M2
com justificativa de que o design já tolera por construção (RNF-02).

## Para o M1

Escopo muda de fundação técnica para conteúdo de design: rotina de
humano, estados de alerta, os 3 objetivos, captura/resgate, HUD
mínimo — a fase MVP inteira (GDD seções 5.2 a 5.7, 6.2, 6.3, 7.1
básica, 8.1). Vale revisitar a posição da escada e a proporção de
alguns cômodos do greybox quando o level design de verdade entrar
(ver docs/backlog.md).
