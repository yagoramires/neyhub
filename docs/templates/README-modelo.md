# <Nome do app>

<Uma linha do que o app faz.>

![<Nome>](docs/print.png)

<!-- Print: só com dados de exemplo (modo --snapshots/--render). Sem print, apague a linha acima. -->

## Instalar

<Hoje: build local (veja "Build local"). Apps com release: baixar o .zip, arrastar para Aplicativos e, na primeira vez, botão direito → Abrir (aviso do Gatekeeper). Só onde há download.>

Instalador `.dmg` e instalação pelo NeyHub chegam na próxima versão.

## Permissões

<Cada permissão que o app pede e por quê. Sem permissão: "Não pede nenhuma permissão.">

## Como usar

<Passo a passo curto e o que cada parte faz.>

## Atalhos

<Tabela de atalhos, vindos do código. Sem atalho: uma linha dizendo isso.>

## Modos de exibição

<Aparência, densidade, tema, ícone da barra. Sem opções: uma linha dizendo isso.>

## Atualizações

<Como o app se atualiza hoje. Sem atualização automática: uma linha honesta.>

## Build local

<Command Line Tools, scripts/setup-signing.sh (uma vez), scripts/build.sh --run.>

<App que também é plugin do NeyHub: dizer que o avulso chama `HubCheck.leaveForHub` ao abrir. Só nesse caso o
Info.plist declara `NeyHubAware = true`, que faz o NeyHub não mostrar o alerta dele quando o avulso abre.>

## Patch notes

Veja o [CHANGELOG](CHANGELOG.md).

## Licença

[MIT](LICENSE)
