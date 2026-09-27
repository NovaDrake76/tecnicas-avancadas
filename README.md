# Kiwi Empire

Jogo de airsoft em primeira pessoa feito para a disciplina **Técnicas Avançadas de Desenvolvimento de Jogos** (Atividade 1 - Airsoft).

Você é um operador infiltrado em bases do império kiwi. As armas são de airsoft e as BBs são simuladas de verdade: arrasto do ar, efeito Magnus do hop-up, massa da esfera e energia da mola. Dá para jogar sozinho ou em dupla na mesma rede.

## Integrantes

- Nathan Araújo Marques
- Fellipe Zanathan dos Santos Souza
- Daniel Coelho dos Santos

## Vídeo de demonstração

https://youtu.be/s6a-WY6TWhE

## Download

Não precisa instalar nada, é só extrair e abrir.

| Sistema | Arquivo |
|---|---|
| Windows | [tecnicas-avancadas-windows.zip](https://github.com/NovaDrake76/tecnicas-avancadas/releases/latest/download/tecnicas-avancadas-windows.zip) |
| Linux | [tecnicas-avancadas-linux.zip](https://github.com/NovaDrake76/tecnicas-avancadas/releases/latest/download/tecnicas-avancadas-linux.zip) |

- **Windows:** extraia o zip e abra `tecnicas-avancadas.exe`.
- **Linux:** extraia o zip, rode `chmod +x tecnicas-avancadas.x86_64` e abra o executável.

Os arquivos `.pck` e a biblioteca `libterrain` precisam ficar na mesma pasta do executável.

## Motor e versão

- **Godot 4.7.2** (renderizador Forward+), scripts em **GDScript**
- Física: **Jolt Physics**, a 120 ticks por segundo
- Terreno: addon [Terrain3D](https://github.com/TokisanGames/Terrain3D) 1.0.2

Para abrir o projeto, importe a pasta no Godot 4.7.2 e aperte F5. A cena inicial é o menu (`UI/main_menu.tscn`).

## Objetivo do jogo

Cada missão acontece em uma base inimiga e tem objetivos próprios. Nas três missões atuais o objetivo é entrar, roubar um item (uma maleta ou um registro) e chegar no ponto de extração. Não é obrigatório derrubar todos os inimigos, e jogar escondido vale mais do que sair atirando.

Se um kiwi vê o jogador, ele tem alguns segundos de chamada no rádio antes de avisar a base. Derrubar ele nesse tempo mantém o silêncio. Se o alarme sobe, a guarnição inteira vai atrás do último lugar em que o jogador foi visto, e uma ave corre até a sirene para chamar reforços.

A missão falha se o jogador fica sem vida. Em dupla, quem cai pode ser levantado pelo parceiro, e a missão só falha se os dois caírem.

## Regra de progressão

- O jogo começa no esconderijo, que tem a bancada de armas, o estande de tiro e o quadro de missões.
- As missões 1 e 2 começam abertas. **Cada missão concluída libera a próxima.**
- No fim da missão o jogador recebe uma nota de F até A+, calculada com três pesos: furtividade (40%), precisão (30%) e tempo em relação ao tempo par da missão (30%).
- A pontuação vira dinheiro na bancada, usado para comprar molas, motores, BBs mais pesadas, carregadores e armas novas.
- Repetir uma missão só paga a diferença em relação à melhor pontuação anterior, então melhorar compensa e só repetir não.

| Missão | Fase | Objetivo |
|---|---|---|
| 1 | The Motor Pool | Pegar a maleta do telêmetro na casa e sair pelo sudeste |
| 2 | The Ridge Post | Pegar a outra maleta dentro do posto murado e sair pelo muro sul |
| 3 | The Village | Pegar o registro de sinais na casa de comando e descer pela estrada |

## Controles

| Tecla | Ação |
|---|---|
| W A S D | Andar |
| Mouse | Olhar |
| Espaço | Pular |
| Shift | Correr |
| Ctrl (segurar) | Agachar |
| Z | Deitar |
| Alt + A / D | Inclinar para o lado |
| Botão esquerdo | Atirar |
| Botão direito | Mirar |
| Roda do mouse | Ajustar o hop-up (com o binóculo levantado, é o zoom) |
| F | Trocar o modo de tiro (semi / auto) |
| R | Recarregar |
| R (segurar) | Olhar o carregador da arma e os que estão na bolsa |
| 1 a 5 | Escolher a arma |
| Q / Tab | Próxima arma / arma anterior |
| E | Interagir (pegar munição, objetivos, carregar corpos, levantar o parceiro) |
| V | Nocaute silencioso pelas costas |
| B | Binóculo |
| G | Arremessar a granada |
| Botão do meio | Marcar um ponto para o parceiro |
| Esc | Pausa e opções |
| Enter | Pular o briefing / fechar a tela de resultado |

## Armas

| Arma | Tipo | Energia | Cadência | Modos |
|---|---|---|---|---|
| KESTREL | Fuzil elétrico (AEG) | 1,50 J | 5 disparos/s | semi e auto |
| SHRIKE | Espingarda (pump), 3 esferas por cartucho | 1,50 J por cartucho | 1,5 disparos/s | semi |
| HARRIER | Pistola pesada (gás) | 0,90 J | 5 disparos/s | semi |
| MERLIN | Pistola automática (gás) | 0,81 J | 20 disparos/s | semi e auto |
| OSPREY | Fuzil de ferrolho com luneta | 2,25 J | 0,75 disparos/s | semi |

O jogador começa com a KESTREL e a HARRIER. As outras são compradas na bancada.

## Decisões de modelagem

**Energia e velocidade.** A energia do disparo vem da mola: `E = ½ · k · x²`. A velocidade de saída é calculada a cada tiro com a massa da BB que está no carregador: `v = √(2E / m)`. Nenhuma velocidade é fixa no código. Com a mola padrão (1,5 J), uma BB de 0,20 g sai a 122 m/s e uma de 0,32 g sai a 97 m/s.

**Arrasto.** Cada BB é um corpo rígido com massa real (0,20 g a 0,32 g) e raio real de 3 mm. A cada tick aplicamos `F = ½ · ρ · Cd · A · v²` no sentido contrário à velocidade, com ρ = 1,225 kg/m³ e Cd = 0,47 (esfera).

**Hop-up (Magnus).** O backspin gera uma força perpendicular à velocidade, proporcional a `√v · BackspinDrag`. O jogador regula o `BackspinDrag` com a roda do mouse. Pouco hop-up e a BB cai cedo, demais e ela sobe.

**Cadência.** `disparos/s = RPM / (60 · N)`, onde N é o número de rotações do motor por disparo. Nas armas sem motor (pump, gás e ferrolho) o RPM é o ritmo do mecanismo e N = 1, assim a mesma fórmula vale para todas.

**Munição.** Um disparo gasta exatamente uma unidade do carregador. Na espingarda a unidade é o cartucho, que solta 3 esferas dividindo a energia. Cada carregador guarda a própria contagem e a massa das suas BBs. Na recarga o carregador usado volta para a bolsa com o que sobrou, nada é jogado fora. Munição de outro tipo é recusada e o jogo mostra o motivo.

**Tamanho visual x tamanho físico.** A malha da BB é desenhada maior do que ela é para dar para enxergar, mas a física usa o raio real. Nenhum valor físico é tirado do tamanho do modelo.

**Física a 120 Hz com colisão contínua.** Uma BB a 120 m/s anda 1 metro por tick e tem 6 mm de diâmetro. Sem detecção contínua de colisão ela atravessaria os alvos.

**Cada estado mora no sistema responsável por ele.** O carregador é dono da munição e da massa da BB. A arma é dona da energia, do RPM, do modo de tiro e do hop-up. A BB é dona da própria física depois do disparo. O HUD só desenha o que recebe por sinais.

**Inimigos.** Cada kiwi é uma máquina de estados (calmo, desconfiado, chamando no rádio, caçando, fugindo para a sirene, caído) com componentes separados para visão, voz, corpo e arma. A visão é um cone com alcance que depende da postura do jogador: em pé ele é visto de mais longe do que agachado ou deitado. O caminho dos inimigos usa uma malha de navegação gerada quando a fase carrega.

**Jogo em dupla.** O jogo sempre roda como servidor, mesmo sozinho, então existe um caminho de código só. Pela rede passam a posição, a rotação, a cabeça e a arma em mãos de cada jogador. O servidor decide tudo que muda o mundo: inimigos, alarme, objetivos e dano.

## Organização do projeto

| Pasta | Conteúdo |
|---|---|
| `Autoload/` | Sistemas globais: missão e pontuação, alarme, esquadrão, bancada, som, rede, configurações |
| `Player/` | Jogador e seus componentes |
| `Guns/` | Armas, carregadores e BBs |
| `Characters/Enemy/` | Inimigos |
| `Components/` | Peças reutilizáveis (objetivos, interação, visão, navegação) |
| `Levels/` | Fases, esconderijo e terrenos |
| `HUD/` e `UI/` | Interface do jogo, menus, quadro de missões e briefing |
| `Models/`, `Textures/`, `Sounds/`, `Fonts/`, `Shaders/` | Assets |
