# A ponte JNI: o nome da classe e do metodo e o que o nucleo exporta
# (Java_app_escalibur_wallet_nucleo_Nucleo_chamar). Nao podem mudar.
-keep class app.escalibur.wallet.nucleo.Nucleo { native <methods>; }

# O transporte de rede do nucleo: o JNI_OnLoad procura esta classe e estes dois metodos pelo nome.
# Se sumirem, o nucleo fica sem rede.
-keep class app.escalibur.wallet.nucleo.Rede {
    public static byte[] requisitar(long, java.lang.String, java.lang.String, java.lang.String[], byte[], int, int, int);
    public static void cancelar(long);
}
