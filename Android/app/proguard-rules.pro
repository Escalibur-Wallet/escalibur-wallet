# A ponte JNI: o nome da classe e do metodo e o que o nucleo exporta
# (Java_app_escalibur_wallet_nucleo_Nucleo_chamar). Nao podem mudar.
-keep class app.escalibur.wallet.nucleo.Nucleo { native <methods>; }

# O transporte de rede do nucleo: o JNI_OnLoad procura esta classe e estes dois metodos pelo nome.
# Se sumirem, o nucleo fica sem rede.
-keep class app.escalibur.wallet.nucleo.Rede {
    public static byte[] requisitar(long, java.lang.String, java.lang.String, java.lang.String[], byte[], int, int, int);
    public static void cancelar(long);
}

# O cofre: o JNI_OnLoad procura cada metodo pelo nome (Kit/Sources/Android/EscaliburAndroid/Java.swift).
-keep class app.escalibur.wallet.nucleo.Cofre {
    public static byte[] ler(java.lang.String, byte[]);
    public static int gravar(java.lang.String, byte[], int, byte[], boolean);
    public static int apagar(java.lang.String);
    public static int apagarTudo();
    public static int sondar(java.lang.String);
    public static int criarChave(java.lang.String);
    public static int sondarChave(java.lang.String);
    public static void apagarChave(java.lang.String);
    public static byte[] embrulhar(java.lang.String, byte[], byte[]);
    public static byte[] desembrulhar(java.lang.String, byte[], byte[], java.lang.String);
    public static byte[] desembrulharVigiando(java.lang.String, byte[], java.lang.String, java.lang.String, byte[]);
    public static int estadoDaBiometria();
    public static byte[] cadastroDaBiometria();
    public static byte[] boot();
}
