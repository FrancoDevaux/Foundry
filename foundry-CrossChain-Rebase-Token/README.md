# Cross Chain Rebase Token

## Protocol Deposit Mechanism:
- ``Requirement``: Vamos a crear un protocolo que permita a los usurios depositar en una bódega y a cambio recibir *Rebase Token* que representan su saldo subyacente

- ``Implementation``: Los usuarios interactuarán con un contrato inteligente Vault para depositar un activo base (por ejemplo, ETH o una stablecoin ERC20). A cambio de su depósito, el Vault facilitará la acuñación de una cantidad equivalente de nuestro Token de Rebase para el usuario. Estos tokens representan el derecho proporcional del usuario sobre los activos mantenidos dentro del Vault, incluyendo cualquier interés ganado con el tiempo.


## Rebase Token Dynamic Balances:
- `Requirement`: La función **balanceOf** del Rebase Toekn es "dinámica" para mostrar el balance cambiante a lo largo del tiempo.

- `Clarification`: El saldo de tokens de un usuario debería mostrar un **incremento** lineal basado en la tasa de interés aplicable.

- `Interest Realization Mechanism`: Este es un aspecto crucial del diseño. La función estándar '**balanceOf**' en tokens tipo *ERC20* es una función de "**view**", lo que significa que no puede modificar el estado de la blockchain (como la acuñación de nuevos tokens). Mint tokens directamente cada vez que alguien verifica su balance requeriría transacciones y sería prohibitivamente caro e impráctico.

- `Solution`: Distinguimos entre la acumulación conceptual de intereses y la acuñación real de tokens.
   - El interés se acumula matemáticamente con el tiempo según la tasa del usuario.
   - La función **balanceOf** calculará y devolverá el saldo teórico actual del usuario ("*principal inicial + intereses acumulados*"), proporcionando una visión actualizada sin cambiar el estado.
   - La acuñación real de los tokens de interés acumulado para actualizar el balance interno del usuario registrado en la blockchain solo ocurre cuando el usuario activa una acción que modifica el estado. Estas acciones incluyen *depositar* más fondos (**minting**), retirar fondos (**burning**), transferir tokens o, en la futura versión cross-chain, hacer un puente con los tokens. La actualización del saldo interno ocurre justo antes de que se procese la acción principal (depósito, transferencia, etc.).


## Understanding the Interest Rate Mechanism:

- Un sistema de tasas de interés único es fundamental para el diseño de este token de rebase, cuyo objetivo es recompensar a los primeros participantes.

- `Requirement`: "Interest rate".

- `Mechanism Details`:
  - "Se establece una tasa de interés individual para cada usuario, basada en una tasa de interés global del protocolo vigente en el momento en que el usuario deposita en el vault." 

  - "Esta tasa de interés global solo puede disminuir para incentivar/recompensar a los primeros usuarios."

- `Implementation`:
  - Existe una tasa de **globalInterestRate** para todo el protocolo, controlada por un rol autorizado (por ejemplo, el propietario).
  - Fundamentalmente, el propietario solo puede disminuir esta tasa de globalInterestRate con el tiempo; nunca se puede aumentar.
  - Cuando un usuario realiza su primer depósito en la Bóveda, el protocolo lee la tasa de globalInterestRate actual.
  - Esta tasa se guarda como **userInterestRate** personal.
  - Esta tasa de *userInterestRate* permanecerá fija a partir de ese momento, asociada al capital que depositó.
#

# Important Considerations !!

- `Incremental Development`: Comenzar con una versión de cadena única simplifica el desarrollo inicial y el proceso de pruebas antes de introducir las complejidades de la comunicación entre cadenas (CCIP).

- `Complexity`: Rebase Token son significativamente **más complejos** que los tokens ERC20 estándar debido a su suministro dinámico y cálculos de balance. 

- `Interest Realization`: Comprender claramente la diferencia entre el saldo calculado que muestra *balanceOf* (acumulación conceptual) y la actualización real de los saldos internos mediante la acuñación durante las operaciones que modifican el estado es crucial.

- `Early Adopter Incentive`: La disminución de la tasa de interés global, aunada a las tasas fijas para los usuarios al momento del depósito, es una elección de diseño deliberada para incentivar la participación temprana en el protocolo.





