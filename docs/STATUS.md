# Estado real do projeto

A Alpha 0.6 teve boot e DHCP demonstrados pelo usuário no VirtualBox. A Alpha 0.7, originalmente empacotada fora do GitHub, teve testes de cliente e agente contra API simulada; não se confirmou a inicialização completa da ISO Alpha 0.7.

O workflow neste repositório é um **novo** mecanismo de compilação a partir de fontes e pacotes Ubuntu; ainda requer execução e revisão dos logs no GitHub Actions. Não promete equivalência binária com a ISO Alpha 0.7 construída anteriormente.

Base mínima: Linux com /init em C, console ocultável com F1/F2/Esc, rede DHCP em VM, integração com API compatível, executor com lista fechada. Não há IA local embarcada, desktop gráfico real, instalação autônoma de programas, persistência nem versão para produção.
