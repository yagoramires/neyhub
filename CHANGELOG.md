# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.1.0] - 2026-10-25
### Adicionado
- Loja com seis apps: Aero, Dose, Capture, Deck, Pauta e Hub, em cards com o ícone de cada um e separados em Instalados e Disponíveis. Instalar baixa o pacote do GitHub, confere a assinatura e o app já começa a rodar; no card ficam atualizar, desinstalar, modo de exibição, configurações e novidades de cada versão. App ainda sem release aparece como "Em breve".
- Apps dentro do NeyHub: a tela de cada app abre na janela do NeyHub; cada um escolhe Tela, Barra de menus ou Os dois (app sem tela só mostra ou esconde o ícone).
- Tela de Permissões: Acessibilidade, Notificações, Gravação de Tela e Microfone (opcional) concedidas uma vez para o NeyHub valem para todos os apps; o botão abre o painel certo dos Ajustes. A Rede local do Hub o macOS pergunta sozinho.
- Avisos centralizados: as notificações dos apps passam pelo NeyHub e o toque leva ao app, mesmo quando é ele que abre o NeyHub. Sair ou reiniciar mantém os avisos na Central; desinstalar tira os do app.
- Retorno de login (`hubmac://`): o login do SmartThings volta para o Hub dentro do NeyHub, ou para o Hub avulso se ele estiver aberto; sem ninguém esperando, aparece "Nenhum app esperava este login".
- Hub exige macOS 15: num macOS 14 o card mostra "Precisa do macOS 15.0" em vez de tentar carregar.
- Ícones do NeyHub no Dock e na barra de menus, cada um ocultável (sempre sobra um).
- Janela de 1100 × 680 na primeira abertura; depois ela lembra o tamanho e a posição.
- Acordado: switch na barra lateral que não deixa o Mac dormir, nem com a tampa fechada. Pede a senha de administrador uma vez, só desliga quando você manda e mostra sempre o estado real do sistema. Opcional na barra de menus.
- App avulso aberto: o NeyHub pergunta antes de iniciar o plugin; pausado ao abrir, o app começa quando o avulso fecha.
- Atualização automática do NeyHub e dos apps: checa 5 s depois de abrir e a cada 6 h, baixa em segundo plano, aplica no próximo início (ou em "Reiniciar agora") e mostra as novidades depois.
- Ícone próprio ("ney" branco sobre "hub" verde-limão, fundo grafite), tema Grafite, item de login, instância única e instalador `.dmg`.
- NeyKit para os apps: contrato de plugin v1, tema Grafite e tipos comuns; NeyKitApp para as cascas avulsas (atualização, novidades e checagem do NeyHub).
