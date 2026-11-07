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
    public static byte[] publica(java.lang.String);
    public static byte[] abrirChave(java.lang.String, byte[], java.lang.String);
    public static byte[] abrirChaveVigiando(java.lang.String, byte[], java.lang.String, java.lang.String, byte[]);
    public static byte[] semente(java.lang.String, byte[], boolean);
    public static int temStrongBox();
    public static int estadoDaBiometria();
    public static byte[] cadastroDaBiometria();
    public static byte[] boot();
}

# Os eventos do nucleo (o andamento das telas): o JNI_OnLoad procura este metodo pelo nome. Sem ele, a
# ligacao inteira falha e o app fica sem rede e sem cofre.
-keep class app.escalibur.wallet.nucleo.Eventos {
    public static void emitir(java.lang.String, java.lang.String);
}

# O commit e a arvore de onde o app saiu ficam inteiros no dex: o gerar-aab.sh confere os dois no APK e no AAB,
# e quem audita le no pacote. Sem isto o R8 calculava o que a tela de Ajustes usa e apagava o resto
# (quarta passada da auditoria de 03/11/2026).
-keep class app.escalibur.wallet.BuildConfig {
    public static final java.lang.String COMMIT_DE_ORIGEM;
    public static final java.lang.String ARVORE_DE_ORIGEM;
}
