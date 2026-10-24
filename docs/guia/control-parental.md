# Control parental

Oculta categorías con un PIN para que no aparezcan hasta desbloquear. Necesita una
[cuenta](cuenta-y-sincronizacion.md) iniciada: sin sesión, el interruptor aparece
desactivado con el aviso "Inicia sesión para usar el control parental.", y es la cuenta
la que permite recuperar el PIN si lo olvidas.

## Pasos

1. Inicia sesión en **Ajustes** > Cuenta.
2. En **Ajustes** > Contenido, activa **Control parental con PIN**.
3. Crea un PIN nuevo y repítelo; **Aceptar** lo guarda. Si no coinciden, se avisa. Si
   cancelas, el control parental se queda apagado.

   ![Crear un PIN](img/pin.png)

4. Pulsa **Elegir categorías** y marca las que quieras bloquear.
5. Desde ese momento esas categorías desaparecen. Para verlas, pulsa **Desbloquear** e
   introduce el PIN.

Para apagarlo, desactiva el interruptor e introduce el PIN: el control parental se
desactiva y el PIN se borra. La próxima vez que lo actives crearás uno nuevo.

## Si olvidas el PIN

En la ventana que pide el PIN, pulsa **¿Olvidaste el PIN?**. Te llega un correo al email
de tu cuenta con un código; escríbelo y crea un PIN nuevo. El control parental sigue
activo. Si el código está mal o ha pasado demasiado tiempo, se avisa con "El código no
es correcto o ha caducado." y puedes pedir otro.

![Control parental activado](img/ajustes-control-parental.png)

## Ocultar contenido adulto

El interruptor **Ocultar contenido adulto** quita las categorías con XXX, Adult, +18 y
similares en el nombre. Mientras el control parental está activo, no se puede cambiar sin el PIN.

## Consejos y límites

- El PIN y las categorías bloqueadas **no salen del dispositivo**: no se sincronizan ni
  van en las copias de ajustes, y un fichero importado no puede saltarse el PIN.
- Al **cerrar sesión** con el control parental activo se pide el PIN: si es correcto, se
  desactiva el control parental, se borra el PIN y se cierra la sesión; si cancelas, la
  sesión sigue abierta.
