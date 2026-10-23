// As moedas 3D do site: WebGL escrito aqui, sem biblioteca, no mesmo espirito do app
// (nada baixado de fora). Carregado so depois da pagina, e so quando vale a pena: o
// site.js nao chama este arquivo com "reduzir movimento", sem WebGL, em aparelho fraco
// ou com economia de dados, e a pagina mostra a imagem parada no lugar.
//
// Cada moeda e um cilindro com borda chanfrada e serrilhada. As faces sao desenhadas na
// hora num canvas 2D: a cor (esmalte da marca da rede, metal do aro e do simbolo) e o
// relevo (altura, metal e aspereza), que o shader le para a luz bater no aro, nas
// contas e no simbolo. A luz e um estudio calculado no shader: caixas de luz suaves,
// como as de foto de produto, que o metal reflete.
//
// Os simbolos das redes sao os do Simple Icons (CC0, versao 16.33.0; THIRD_PARTY_NOTICES.md).
// As marcas sao dos seus donos e aparecem so para identificar cada moeda.
(function () {
  "use strict";

  var CAMINHOS = {
    "bitcoin": "M23.638 14.904c-1.602 6.43-8.113 10.34-14.542 8.736C2.67 22.05-1.244 15.525.362 9.105 1.962 2.67 8.475-1.243 14.9.358c6.43 1.605 10.342 8.115 8.738 14.548v-.002zm-6.35-4.613c.24-1.59-.974-2.45-2.64-3.03l.54-2.153-1.315-.33-.525 2.107c-.345-.087-.705-.167-1.064-.25l.526-2.127-1.32-.33-.54 2.165c-.285-.067-.565-.132-.84-.2l-1.815-.45-.35 1.407s.975.225.955.236c.535.136.63.486.615.766l-1.477 5.92c-.075.166-.24.406-.614.314.015.02-.96-.24-.96-.24l-.66 1.51 1.71.426.93.242-.54 2.19 1.32.327.54-2.17c.36.1.705.19 1.05.273l-.51 2.154 1.32.33.545-2.19c2.24.427 3.93.257 4.64-1.774.57-1.637-.03-2.58-1.217-3.196.854-.193 1.5-.76 1.68-1.93h.01zm-3.01 4.22c-.404 1.64-3.157.75-4.05.53l.72-2.9c.896.23 3.757.67 3.33 2.37zm.41-4.24c-.37 1.49-2.662.735-3.405.55l.654-2.64c.744.18 3.137.524 2.75 2.084v.006z",
    "ethereum": "M11.944 17.97L4.58 13.62 11.943 24l7.37-10.38-7.372 4.35h.003zM12.056 0L4.69 12.223l7.365 4.354 7.365-4.35L12.056 0z",
    "solana": "m23.8764 18.0313-3.962 4.1393a.9201.9201 0 0 1-.306.2106.9407.9407 0 0 1-.367.0742H.4599a.4689.4689 0 0 1-.2522-.0733.4513.4513 0 0 1-.1696-.1962.4375.4375 0 0 1-.0314-.2545.4438.4438 0 0 1 .117-.2298l3.9649-4.1393a.92.92 0 0 1 .3052-.2102.9407.9407 0 0 1 .3658-.0746H23.54a.4692.4692 0 0 1 .2523.0734.4531.4531 0 0 1 .1697.196.438.438 0 0 1 .0313.2547.4442.4442 0 0 1-.1169.2297zm-3.962-8.3355a.9202.9202 0 0 0-.306-.2106.941.941 0 0 0-.367-.0742H.4599a.4687.4687 0 0 0-.2522.0734.4513.4513 0 0 0-.1696.1961.4376.4376 0 0 0-.0314.2546.444.444 0 0 0 .117.2297l3.9649 4.1394a.9204.9204 0 0 0 .3052.2102c.1154.049.24.0744.3658.0746H23.54a.469.469 0 0 0 .2523-.0734.453.453 0 0 0 .1697-.1961.4382.4382 0 0 0 .0313-.2546.4444.4444 0 0 0-.1169-.2297zM.46 6.7225h18.7815a.9411.9411 0 0 0 .367-.0742.9202.9202 0 0 0 .306-.2106l3.962-4.1394a.4442.4442 0 0 0 .117-.2297.4378.4378 0 0 0-.0314-.2546.453.453 0 0 0-.1697-.196.469.469 0 0 0-.2523-.0734H4.7596a.941.941 0 0 0-.3658.0745.9203.9203 0 0 0-.3052.2102L.1246 5.9687a.4438.4438 0 0 0-.1169.2295.4375.4375 0 0 0 .0312.2544.4512.4512 0 0 0 .1692.196.4689.4689 0 0 0 .2518.0739z",
    "tether": "M18.7538 10.5176c0 .6251-2.2379 1.1483-5.2381 1.2812l.0028.0007c-.0848.0064-.5233.0325-1.5012.0325-.7778 0-1.33-.0233-1.5237-.0325-3.0059-.1322-5.2495-.6555-5.2495-1.2819s2.2436-1.149 5.2495-1.2834v2.0442c.1965.0142.7594.0474 1.5372.0474.9334 0 1.4008-.0389 1.4849-.0466V9.2356c2.9994.1337 5.2381.657 5.2381 1.282zm5.19.5466L12.1248 22.389a.1803.1803 0 0 1-.2496 0L.0562 11.0635a.1781.1781 0 0 1-.0382-.2079l4.3762-9.1921a.1767.1767 0 0 1 .1626-.1026h14.8878a.1768.1768 0 0 1 .1612.1032l4.3762 9.1922a.1782.1782 0 0 1-.0382.2079zm-4.478-.4038c0-.8068-2.5515-1.4799-5.9473-1.6369V7.195h4.186V4.4055H6.3076V7.195h4.1852v1.8286c-3.4018.1562-5.9601.83-5.9601 1.6376 0 .8075 2.5583 1.4806 5.9601 1.6376v5.8618h3.025v-5.8639c3.394-.1563 5.948-.8295 5.948-1.6363z",
    "ripple": "M5.52 2.955A3.521 3.521 0 001.996 6.48v2.558A2.12 2.12 0 010 11.157l.03.562-.03.561a2.12 2.12 0 011.996 2.121v2.948a3.69 3.69 0 003.68 3.696v-1.123a2.56 2.56 0 01-2.557-2.558v-2.963a3.239 3.239 0 00-1.42-2.682 3.26 3.26 0 001.42-2.682V6.48A2.412 2.412 0 015.52 4.078h.437V2.955zm12.538 0v1.123h.437a2.39 2.39 0 012.386 2.401v2.558a3.26 3.26 0 001.42 2.682 3.239 3.239 0 00-1.42 2.682v2.963a2.56 2.56 0 01-2.557 2.558v1.123a3.69 3.69 0 003.68-3.696V14.4A2.12 2.12 0 0124 12.281l-.03-.562.03-.561a2.12 2.12 0 01-1.996-2.12V6.478a3.518 3.518 0 00-3.509-3.524zM6.253 7.478l3.478 3.259a3.393 3.393 0 004.553 0l3.478-3.26h-1.669l-2.65 2.464a2.133 2.133 0 01-2.886 0L7.922 7.478zm5.606 4.884a3.36 3.36 0 00-2.128.886l-3.493 3.274h1.668l2.667-2.495a2.133 2.133 0 012.885 0l2.65 2.495h1.67l-3.494-3.274a3.36 3.36 0 00-2.425-.886z",
    "the-open-network": "M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zM7.902 6.697h8.196c1.505 0 2.462 1.628 1.705 2.94l-5.059 8.765a.86.86 0 0 1-1.488 0L6.199 9.637c-.758-1.314.197-2.94 1.703-2.94zm4.844 1.496v7.58l1.102-2.128 2.656-4.756a.465.465 0 0 0-.408-.696h-3.35zM7.9 8.195a.464.464 0 0 0-.408.694l2.658 4.754 1.102 2.13V8.195H7.9z",
    "dogecoin": "M12.288 7.908h-1.715v3.38h2.697v1.415h-2.697v3.38h1.799c.462 0 3.794.052 3.789-3.933-.005-3.984-3.232-4.242-3.873-4.242zM12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm.472 18.481H8.126v-5.778H6.594v-1.415h1.532V5.511h3.73c.882 0 6.727-.183 6.727 6.594-.001 6.888-6.111 6.376-6.111 6.376z",
    "cardano": "M6.5765 11.92c-.0488.8906.6316 1.653 1.5219 1.7056h.0934c.8928-.0006 1.6161-.725 1.6155-1.6178-.0006-.8928-.725-1.6161-1.6178-1.6155-.8578.0006-1.5658.6711-1.613 1.5277Zm-6.025-.416c-.288-.0161-.5345.2042-.5507.4922-.0161.288.2042.5345.4922.5507.2878.0161.5343-.204.5506-.4918.0167-.2876-.2029-.5343-.4905-.5509H.5514Zm5.9226-8.9645c.257-.1309.3593-.4453.2284-.7024-.1309-.257-.4453-.3593-.7024-.2284-.2558.1302-.3585.4424-.2301.6991.13.2582.4448.3622.703.2322.0003-.0002.0007-.0003.001-.0005Zm1.6397 2.8589c.398-.2006.558-.6859.3573-1.0839-.2006-.398-.6859-.558-1.0839-.3573-.3978.2006-.5579.6856-.3575 1.0835.2007.398.686.5581 1.0842.3578ZM2.597 7.3645c.3072.2013.7194.1154.9206-.1918.2013-.3072.1154-.7194-.1918-.9206-.3072-.2013-.7194-.1154-.9206.1918 0 .0001-.0001.0002-.0002.0003-.201.3072-.1151.7191.192.9203Zm.9824 3.8515c-.4453-.0254-.827.3149-.8524.7603s.3149.827.7603.8524c.4453.0254.827-.3149.8524-.7603v-.0006c.0251-.4451-.3152-.8264-.7603-.8518Zm-.8915 5.4221c-.328.1652-.46.565-.2948.893.1652.328.565.46.893.2948.328-.1652.46-.565.2948-.893l-.0002-.0004c-.1645-.3276-.5633-.4598-.8909-.2954-.0006.0003-.0013.0006-.0019.001Zm3.136-7.0931c.4386.2876 1.0274.1653 1.315-.2734.2876-.4386.1653-1.0274-.2734-1.315-.4386-.2876-1.0273-.1653-1.3149.2732-.2878.4381-.166 1.0266.2721 1.3144.0004.0003.0008.0005.0012.0008Zm9.9501-4.2106c.3729.2447.8737.1408 1.1184-.2321.2447-.3729.1408-.8737-.2321-1.1184-.3729-.2447-.8737-.1408-1.1184.2321 0 .0001-.0001.0002-.0002.0003-.2447.3726-.141.8729.2316 1.1176.0003.0002.0005.0003.0008.0005Zm1.6563-2.8499c.2413.1579.565.0904.723-.151s.0904-.565-.151-.723c-.241-.1577-.5642-.0906-.7224.1501-.1584.241-.0915.5648.1495.7233l.0009.0006Zm-1.5296 7.8938c-.8911-.0507-1.6546.6305-1.7053 1.5216-.0507.8911.6305 1.6546 1.5216 1.7053h.0928c.8925 0 1.616-.7235 1.616-1.616 0-.8572-.6693-1.5652-1.5251-1.6134v.0026ZM8.645 9.433c.2737.5459.8331.8896 1.4438.887.8925-.0002 1.6159-.7238 1.6157-1.6163 0-.2526-.0593-.5018-.1731-.7273-.4017-.7971-1.3735-1.1176-2.1706-.7158-.7971.4017-1.1176 1.3735-.7158 2.1706v.0019Zm12.6669-2.0704c.3273-.1666.4575-.567.2909-.8943-.1666-.3273-.567-.4575-.8943-.2909-.3259.1659-.4567.5639-.2927.8908.1652.3284.5653.4607.8937.2956.0008-.0004.0015-.0008.0023-.0012Zm-4.096.5146c-.4683.2362-.6565.8074-.4203 1.2757.2362.4683.8074.6565 1.2757.4203.468-.2361.6563-.8066.4207-1.2749-.2364-.4683-.8074-.6568-1.2762-.4211Zm-5.2768-5.6365c.3667.0205.6806-.2601.7011-.6267s-.2601-.6806-.6267-.7011c-.3655-.0205-.6789.2584-.7009.6238-.0225.3662.2562.6813.6224.7038.0014 0 .0028.0002.0042.0002Zm-.0077 4.1837c.5237.0288.9717-.3724 1.0006-.8961.0288-.5237-.3723-.9717-.8961-1.0006-.5231-.0288-.9707.3714-1.0005.8944-.0298.5237.3706.9724.8943 1.0021h.0017Zm-5.1475 9.6992c.4685-.2359.657-.807.421-1.2755-.2359-.4685-.807-.657-1.2755-.421-.4684.2359-.6569.8069-.4211 1.2754.2362.4682.807.6567 1.2755.4211Zm5.76-8.313c-.4881.7459-.2792 1.7463.4667 2.2344s1.7463.2792 2.2344-.4667.2792-1.7463-.4667-2.2344c-.262-.1715-.5683-.263-.8815-.2635-.5452-.0001-1.0538.2744-1.353.7302Zm2.8109 6.7571c-.4015-.7975-1.3735-1.1185-2.171-.7169-.7975.4015-1.1185 1.3735-.7169 2.171.4015.7975 1.3735 1.1185 2.171.7169.0005-.0002.0009-.0005.0014-.0007.7947-.3952 1.1186-1.3598.7235-2.1545-.0026-.0053-.0053-.0105-.0079-.0158Zm2.8211-.112c-.4386-.2876-1.0274-.1653-1.315.2734-.2876.4386-.1653 1.0274.2734 1.315.4386.2876 1.0273.1653 1.3149-.2732.2877-.4386.1654-1.0274-.2731-1.3151h-.0002Zm3.0963-2.4282c.0254-.4453-.3149-.827-.7603-.8524-.4453-.0254-.827.3149-.8524.7603-.0254.4453.3149.827.7603.8524h.0006c.4451.0251.8264-.3152.8518-.7603Zm2.2349-.5741c-.288-.0161-.5345.2042-.5507.4922s.2042.5345.4922.5507c.2878.0161.5343-.204.5506-.4918.016-.288-.2042-.5345-.4922-.551Zm-2.1043 5.1821c-.3073-.2011-.7194-.115-.9205.1923-.2011.3073-.115.7194.1923.9205.3071.201.719.1151.9202-.1918.2013-.3071.1156-.7193-.1916-.9207l-.0004-.0003ZM6.5695 21.5161c-.2411-.1584-.5649-.0913-.7232.1497-.1584.2411-.0913.5649.1497.7232.2411.1584.5649.0913.7232-.1497.158-.2411.091-.5646-.1498-.7232Zm10.9555-.055c-.257.1309-.3593.4453-.2284.7024.1309.257.4453.3593.7023.2284.2558-.1302.3585-.4424.2301-.6991-.1291-.2579-.4428-.3624-.7007-.2333-.0011.0005-.0022.0011-.0033.0016Zm-6.0691-5.2717c.4892-.7465.2806-1.7482-.4659-2.2374-.7465-.4892-1.7482-.2806-2.2374.4659s-.2806 1.7482.4659 2.2374c.2628.1722.5702.2641.8844.2644.5458.0022 1.0553-.2728 1.353-.7302Zm-3.2301 2.4768c-.3729-.2447-.8737-.1408-1.1184.2321-.2447.3729-.1408.8737.2321 1.1184s.8737.1408 1.1184-.2321c0-.0001.0001-.0002.0002-.0003.2445-.3729.1405-.8734-.2323-1.1181Zm3.7664 3.0931c-.3667-.0209-.6808.2594-.7017.6261s.2594.6808.6261.7017c.3658.0208.6795-.2581.7016-.6238.0222-.3666-.2571-.6817-.6236-.7039-.0008 0-.0015 0-.0023-.0001Zm.007-4.1837c-.5237-.0288-.9717.3724-1.0005.8961-.0288.5237.3724.9717.8961 1.0005.5228.0288.9703-.371 1.0004-.8938.0298-.524-.3709-.973-.8949-1.0028h-.0011Zm3.8861 1.0259c-.3976.2022-.556.6884-.3539 1.086.2022.3976.6884.556 1.086.3539.3961-.2014.5551-.685.3558-1.0821-.2-.3987-.6854-.5598-1.0841-.3597-.0013.0007-.0026.0013-.0039.002Z",
    "sui": "M17.636 10.009a7.16 7.16 0 0 1 1.565 4.474 7.2 7.2 0 0 1-1.608 4.53l-.087.106-.023-.135a7 7 0 0 0-.07-.349c-.502-2.21-2.142-4.106-4.84-5.642-1.823-1.034-2.866-2.278-3.14-3.693-.177-.915-.046-1.834.209-2.62.254-.787.631-1.446.953-1.843l1.05-1.284a.46.46 0 0 1 .713 0l5.28 6.456zm1.66-1.283L12.26.123a.336.336 0 0 0-.52 0L4.704 8.726l-.023.029a9.33 9.33 0 0 0-2.07 5.872C2.612 19.803 6.816 24 12 24s9.388-4.197 9.388-9.373a9.32 9.32 0 0 0-2.07-5.871zM6.389 9.981l.63-.77.018.142q.023.17.055.34c.408 2.136 1.862 3.917 4.294 5.297 2.114 1.203 3.345 2.586 3.7 4.103a5.3 5.3 0 0 1 .109 1.801l-.004.034-.03.014A7.2 7.2 0 0 1 12 21.67c-3.976 0-7.2-3.218-7.2-7.188 0-1.705.594-3.27 1.587-4.503z",
    "near": "M21.443 0c-.89 0-1.714.46-2.18 1.218l-5.017 7.448a.533.533 0 0 0 .792.7l4.938-4.282a.2.2 0 0 1 .334.151v13.41a.2.2 0 0 1-.354.128L5.03.905A2.555 2.555 0 0 0 3.078 0h-.521A2.557 2.557 0 0 0 0 2.557v18.886a2.557 2.557 0 0 0 4.736 1.338l5.017-7.448a.533.533 0 0 0-.792-.7l-4.938 4.283a.2.2 0 0 1-.333-.152V5.352a.2.2 0 0 1 .354-.128l14.924 17.87c.486.574 1.2.905 1.952.906h.521A2.558 2.558 0 0 0 24 21.445V2.557A2.558 2.558 0 0 0 21.443 0Z",
    "litecoin": "M12 0a12 12 0 1012 12A12 12 0 0012 0zm-.2617 3.6777h2.584a.3425.3425 0 01.33.4356l-2.0312 6.918 1.9062-.582-.4082 1.3847-1.9238.5605-1.248 4.213h6.6757a.3425.3425 0 01.3282.4374l-.582 2a.4586.4586 0 01-.4395.3301H6.7324l1.7227-5.8223-1.9063.5801.42-1.3613 1.9101-.58 2.4219-8.1798a.4557.4557 0 01.4375-.334Z",
    "binancecoin": "M5.631 3.676 12.001 0l6.367 3.676-2.34 1.358L12 2.716 7.972 5.034l-2.34-1.358Zm12.737 4.636-2.34-1.358L12 9.272 7.972 6.954l-2.34 1.358v2.716l4.026 2.318v4.636L12 19.341l2.341-1.359v-4.636l4.027-2.318V8.312Zm0 7.352v-2.716l-2.34 1.358v2.716l2.34-1.358Zm1.663.96-4.027 2.318v2.717l6.368-3.677V10.63l-2.34 1.358v4.636Zm-2.34-10.63 2.34 1.358v2.716l2.341-1.358V5.994l-2.34-1.358-2.342 1.358ZM9.657 19.926v2.716L12 24l2.341-1.358v-2.716l-2.34 1.358-2.343-1.358Zm-4.027-4.262 2.341 1.358v-2.716l-2.34-1.358v2.716Zm4.027-9.67L12 7.352l2.341-1.358-2.34-1.358-2.343 1.358Zm-5.69 1.358L6.31 5.994 3.968 4.636l-2.34 1.358V8.71l2.34 1.358V7.352Zm0 4.636-2.34-1.358v7.352l6.368 3.677v-2.717l-4.028-2.318v-4.636Z",
    "stellar": "M12.003 1.716c-1.37 0-2.7.27-3.948.78A10.18 10.18 0 0 0 2.66 7.901a10.136 10.136 0 0 0-.797 3.954c0 .258.01.516.027.775a1.942 1.942 0 0 1-1.055 1.88L0 14.934v1.902l2.463-1.26.072-.032v.005l.77-.39.758-.385.066-.039 14.807-7.56 1.666-.847 3.392-1.732V2.694L17.792 5.86 3.744 13.025l-.104.055-.017-.115a8.286 8.286 0 0 1-.071-1.105c0-2.255.88-4.377 2.474-5.977a8.462 8.462 0 0 1 2.71-1.82 8.513 8.513 0 0 1 3.2-.654h.067a8.41 8.41 0 0 1 4.09 1.055l1.628-.83.126-.066a10.11 10.11 0 0 0-5.845-1.853zM24 7.143 5.047 16.808l-1.666.847L0 19.382v1.902l3.282-1.671 2.91-1.485 14.058-7.153.105-.055.016.115c.05.369.072.743.072 1.11 0 2.255-.88 4.383-2.475 5.978a8.461 8.461 0 0 1-2.71 1.82 8.305 8.305 0 0 1-3.2.654h-.06c-1.441 0-2.86-.369-4.102-1.061l-.066.033-1.683.857c.594.418 1.232.776 1.903 1.062a10.11 10.11 0 0 0 3.947.797 10.09 10.09 0 0 0 7.17-2.975 10.136 10.136 0 0 0 2.969-7.18c0-.259-.005-.523-.027-.781a1.942 1.942 0 0 1 1.055-1.88L24 9.044z",
    "polkadot": "M12,0c2.39,0,4.328,1.127,4.328,2.517S14.39,5.034,12,5.034,7.672,3.907,7.672,2.517,9.61,0,12,0Zm0,18.966c2.39,0,4.328,1.127,4.328,2.517S14.39,24,12,24s-4.328-1.127-4.328-2.517S9.61,18.966,12,18.966ZM1.606,6C2.8,3.93,4.747,2.816,5.952,3.511s1.212,2.937.017,5.007S2.828,11.7,1.624,11.007.411,8.07,1.606,6Zm16.427,9.483c1.2-2.07,3.139-3.184,4.343-2.489s1.211,2.936.016,5.006-3.14,3.185-4.344,2.49S16.837,17.553,18.033,15.483ZM1.624,12.993c1.205-.7,3.15.419,4.346,2.489s1.187,4.311-.018,5.007S2.8,20.07,1.607,18,.42,13.689,1.624,12.993ZM18.049,3.512c1.2-.695,3.149.419,4.344,2.489s1.188,4.311-.016,5.007-3.148-.42-4.343-2.49S16.846,4.207,18.049,3.512Z",
    "chainlink": "M12 0L9.798 1.266l-6 3.468L1.596 6v12l2.202 1.266 6.055 3.468L12.055 24l2.202-1.266 5.945-3.468L22.404 18V6l-2.202-1.266-6-3.468zM6 15.468V8.532l6-3.468 6 3.468v6.936l-6 3.468z"
  };

  // O contorno do pentagono do Tether, para tirar o T de dentro dele.
  var PENTAGONO_TETHER = [[0.02, 10.86], [4.39, 1.66], [19.62, 1.66], [23.98, 10.86], [12, 22.44]];

  var PRATA = [196, 198, 204];
  var GRAFITE = [58, 59, 64];

  function avalanche(g) {
    g.lineJoin = "round";
    g.lineWidth = 0.9;
    g.beginPath();
    g.moveTo(5.0, 16.3); g.lineTo(11.33, 4.6); g.lineTo(15.7, 12.4); g.lineTo(11.6, 16.3); g.closePath();
    g.moveTo(13.6, 16.3); g.lineTo(16.3, 11.6); g.lineTo(19.0, 16.3); g.closePath();
    g.fill(); g.stroke();
  }

  function usdc(g) {
    g.lineWidth = 1.75;
    g.lineCap = "butt";
    g.beginPath(); g.arc(12, 12, 8.3, Math.PI * 0.62, Math.PI * 1.38); g.stroke();
    g.beginPath(); g.arc(12, 12, 8.3, -Math.PI * 0.38, Math.PI * 0.38); g.stroke();
    g.font = "700 11.5px Inter, system-ui, sans-serif";
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillText("$", 12, 12.6);
  }

  // A espada do icone do app (wallet-1024.png), nas mesmas proporcoes: a lamina desce
  // ate o aro, como no icone ela sai pela borda.
  function espada(g) {
    var k = 24 / 1024;
    function caixa(x0, y0, x1, y1) { g.rect(x0 * k, y0 * k, (x1 - x0) * k, (y1 - y0) * k); }
    g.beginPath();
    caixa(440, 297, 584, 361);
    caixa(475, 359, 549, 509);
    caixa(209, 507, 815, 558);
    caixa(448, 556, 576, 1200);
    g.fill();
  }

  // Cada moeda: a cor do campo (o fundo do logo da rede) e o simbolo, em metal.
  var MOEDAS = {
    bitcoin: { campo: "#F7931A", simbolo: { d: "bitcoin", modo: "disco", escala: 1.02 } },
    ethereum: { campo: "#627EEA", simbolo: { d: "ethereum", modo: "cheio", escala: 0.6 } },
    solana: { campo: "#16161B", simbolo: { d: "solana", modo: "cheio", escala: 0.56, gradiente: ["#9945FF", "#19FB9B"], esmalte: true }, fosco: true },
    tether: { campo: "#26A17B", simbolo: { d: "tether", modo: "poligono", escala: 0.86 } },
    ripple: { campo: "#EDEDF0", simbolo: { d: "ripple", modo: "cheio", escala: 1.0, recorte: [5.95, 0, 18.1, 24], metal: GRAFITE } },
    "the-open-network": { campo: "#0098EA", simbolo: { d: "the-open-network", modo: "disco", escala: 1.0 } },
    dogecoin: { campo: "#C2A633", simbolo: { d: "dogecoin", modo: "disco", escala: 1.0 } },
    cardano: { campo: "#0033AD", simbolo: { d: "cardano", modo: "cheio", escala: 0.66 } },
    sui: { campo: "#4DA2FF", simbolo: { d: "sui", modo: "cheio", escala: 0.56 } },
    near: { campo: "#00EC97", simbolo: { d: "near", modo: "cheio", escala: 0.5, metal: GRAFITE } },
    litecoin: { campo: "#345D9D", simbolo: { d: "litecoin", modo: "disco", escala: 1.0 } },
    binancecoin: { campo: "#F0B90B", simbolo: { d: "binancecoin", modo: "cheio", escala: 0.6 } },
    stellar: { campo: "#EDEDF0", simbolo: { d: "stellar", modo: "cheio", escala: 0.58, metal: GRAFITE } },
    chainlink: { campo: "#2A5ADA", simbolo: { d: "chainlink", modo: "cheio", escala: 0.56 } },
    polkadot: { campo: "#E6007A", simbolo: { d: "polkadot", modo: "cheio", escala: 0.58 } },
    "avalanche-2": { campo: "#E84142", simbolo: { desenho: avalanche, escala: 0.8 } },
    "usd-coin": { campo: "#2775CA", simbolo: { desenho: usdc, escala: 0.9 } },
    escalibur: { campo: "#FF007B", simbolo: { desenho: espada, escala: 1.0 } },
    verso: { campo: "#1A1A1E", simbolo: { desenho: espada, escala: 1.0 } },
  };

  // MARK: Faces (canvas 2D)

  var LADO = 512;          // cada metade do atlas: cor a esquerda, relevo a direita
  var RAIO_UV = 0.49;      // o raio da face no uv da metade
  var CAMPO = 0.845;       // onde o campo termina e o aro comeca (fracao do raio da face)
  var faces = {};

  function rgb(hex) {
    var n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }

  function borrar(dados, l, raio, vezes) {
    var tmp = new Float32Array(dados.length);
    for (var v = 0; v < vezes; v++) {
      for (var y = 0; y < l; y++) {
        var soma = 0, base = y * l;
        for (var x = -raio; x <= raio; x++) soma += dados[base + Math.min(l - 1, Math.max(0, x))];
        for (x = 0; x < l; x++) {
          tmp[base + x] = soma / (2 * raio + 1);
          soma += dados[base + Math.min(l - 1, x + raio + 1)] - dados[base + Math.max(0, x - raio)];
        }
      }
      for (x = 0; x < l; x++) {
        soma = 0;
        for (y = -raio; y <= raio; y++) soma += tmp[Math.min(l - 1, Math.max(0, y)) * l + x];
        for (y = 0; y < l; y++) {
          dados[y * l + x] = soma / (2 * raio + 1);
          soma += tmp[Math.min(l - 1, y + raio + 1) * l + x] - tmp[Math.max(0, y - raio) * l + x];
        }
      }
    }
  }

  function mascara(def) {
    var c = document.createElement("canvas");
    c.width = c.height = LADO;
    var g = c.getContext("2d");
    var s = def.simbolo;
    var raioCampo = LADO * RAIO_UV * CAMPO;
    var k = (raioCampo * 2 * s.escala) / 24;
    g.translate(LADO / 2, LADO / 2);
    g.scale(k, k);
    g.translate(-12, -12);
    g.fillStyle = "#fff";
    g.strokeStyle = "#fff";
    if (s.desenho) {
      g.save();
      g.beginPath(); g.arc(12, 12, 12 / s.escala, 0, Math.PI * 2); g.clip();
      s.desenho(g);
      g.restore();
    } else if (s.modo === "disco") {
      g.beginPath(); g.arc(12, 12, 12, 0, Math.PI * 2); g.fill();
      g.globalCompositeOperation = "destination-out";
      g.fill(new Path2D(CAMINHOS[s.d]));
    } else if (s.modo === "poligono") {
      g.beginPath();
      PENTAGONO_TETHER.forEach(function (p, i) { if (i) g.lineTo(p[0], p[1]); else g.moveTo(p[0], p[1]); });
      g.closePath(); g.fill();
      g.globalCompositeOperation = "destination-out";
      g.fill(new Path2D(CAMINHOS[s.d]));
    } else {
      if (s.recorte) { g.beginPath(); g.rect(s.recorte[0], s.recorte[1], s.recorte[2] - s.recorte[0], s.recorte[3] - s.recorte[1]); g.clip(); }
      g.fill(new Path2D(CAMINHOS[s.d]));
    }
    var px = g.getImageData(0, 0, LADO, LADO).data;
    var m = new Float32Array(LADO * LADO);
    for (var i = 0; i < m.length; i++) m[i] = px[i * 4 + 3] / 255;
    return m;
  }

  // O que e igual em toda face (o aro, as contas, o guilhoche) sai uma vez so, para a
  // pagina: por pixel, sem raiz nem seno na hora de cada moeda.
  var BASE = null;
  function baseDaFace() {
    if (BASE) return BASE;
    var l = LADO, n = l * l, c = l / 2, raio = l * RAIO_UV;
    var aroA = new Float32Array(n), contaA = new Float32Array(n), guiA = new Float32Array(n), alturaA = new Float32Array(n);
    var contas = 90, raioContas = 0.79, tamConta = 0.0115;
    for (var y = 0; y < l; y++) {
      for (var x = 0; x < l; x++) {
        var dx = (x + 0.5 - c) / raio, dy = (y + 0.5 - c) / raio;
        var r = Math.sqrt(dx * dx + dy * dy), a = Math.atan2(dy, dx), i = y * l + x;
        // Altura: campo baixo, aro alto com chanfro para dentro e um sulco, contas em volta.
        var aro = smooth(CAMPO - 0.02, CAMPO + 0.025, r);
        var h = 0.02 + aro * 0.72 - 0.05 * Math.exp(-Math.pow((r - 0.955) / 0.006, 2)) * aro;
        var setor = (a / (Math.PI * 2)) * contas;
        var dc = (setor - Math.round(setor)) * (Math.PI * 2 / contas) * raioContas, dr = r - raioContas;
        var dist = Math.sqrt(dc * dc + dr * dr) / tamConta;
        var conta = dist < 1 ? Math.sqrt(1 - dist * dist) : 0;
        aroA[i] = aro;
        contaA[i] = conta;
        alturaA[i] = Math.max(h, 0.02 + conta * 0.34);
        // O guilhoche do campo, por baixo do esmalte: ondas finas, como num mostrador.
        guiA[i] = Math.sin(r * 210 + 3.2 * Math.sin(a * 14)) * 0.5 + 0.5;
      }
    }
    BASE = { aro: aroA, conta: contaA, gui: guiA, altura: alturaA };
    return BASE;
  }

  // Cada face e um trabalho em etapas (mascara, borrao, linhas em fatias), feito fora do
  // quadro da animacao, em pedacos de poucos milissegundos: o celular nao trava, e a moeda
  // aparece quando a face fica pronta.
  var fila = [], trabalhando = false, aoPronta = [];
  function pedirFace(id) {
    if (faces[id] || fila.some(function (j) { return j.id === id; })) return;
    fila.push({ id: id, etapa: 0, linha: 0 });
    if (!trabalhando) { trabalhando = true; setTimeout(trabalhar, 0); }
  }
  function trabalhar() {
    var fim = performance.now() + 7;
    while (fila.length && performance.now() < fim) passo(fila[0]);
    if (fila.length) setTimeout(trabalhar, 0);
    else trabalhando = false;
  }
  function passo(j) {
    var l = LADO;
    if (j.etapa === 0) {
      baseDaFace();
      j.etapa = 1;
    } else if (j.etapa === 1) {
      j.def = MOEDAS[j.id] || MOEDAS.bitcoin;
      j.nitida = mascara(j.def);
      j.etapa = 2;
    } else if (j.etapa === 2) {
      j.borrada = new Float32Array(j.nitida);
      borrar(j.borrada, l, 3, 2);
      j.atlas = document.createElement("canvas");
      j.atlas.width = l * 2; j.atlas.height = l;
      j.img = j.atlas.getContext("2d").createImageData(l * 2, l);
      j.etapa = 3;
    } else if (j.etapa === 3) {
      linhas(j, j.linha, Math.min(l, j.linha + 48));
      j.linha += 48;
      if (j.linha >= l) {
        j.atlas.getContext("2d").putImageData(j.img, 0, 0);
        faces[j.id] = j.atlas;
        fila.shift();
        aoPronta.forEach(function (fn) { fn(j.id); });
      }
    }
  }
  function linhas(j, y0, y1) {
    var l = LADO, def = j.def, B = BASE, d = j.img.data;
    var corCampo = rgb(def.campo), metalSimb = def.simbolo.metal || PRATA;
    var grad = def.simbolo.gradiente ? [rgb(def.simbolo.gradiente[0]), rgb(def.simbolo.gradiente[1])] : null;
    var esmalte = !!def.simbolo.esmalte, fosco = !!def.fosco;
    for (var y = y0; y < y1; y++) {
      for (var x = 0; x < l; x++) {
        var i = y * l + x;
        var aro = B.aro[i], conta = B.conta[i], gui = B.gui[i];
        var simbNitido = j.nitida[i];
        var h = Math.max(B.altura[i], 0.02 + smooth(0.08, 0.92, j.borrada[i]) * 0.7);
        var noAro = Math.max(aro, conta > 0 ? 1 : 0);
        var noSimbolo = aro < 0.5 ? smooth(0.0, 1.0, simbNitido) : 0;
        var metal = Math.max(noAro, esmalte ? 0 : smooth(0.25, 0.6, simbNitido));
        var aspero;
        if (noAro > 0.5) aspero = 0.17;
        else if (simbNitido > 0.5) aspero = esmalte ? 0.22 : 0.3;
        else aspero = fosco ? 0.72 : 0.34 + gui * 0.04;
        // Cor: o esmalte do campo, o simbolo (metal ou esmalte) e o metal do aro.
        var luz = 0.94 + gui * 0.09;
        var sr = metalSimb[0], sg = metalSimb[1], sb = metalSimb[2];
        if (grad) {
          var t = Math.min(1, Math.max(0, ((x / l) * 0.6 + (1 - y / l) * 0.4 - 0.22) / 0.56));
          sr = grad[0][0] + (grad[1][0] - grad[0][0]) * t;
          sg = grad[0][1] + (grad[1][1] - grad[0][1]) * t;
          sb = grad[0][2] + (grad[1][2] - grad[0][2]) * t;
        }
        var o = (y * l * 2 + x) * 4;
        d[o] = mix(mix(corCampo[0] * luz, sr, noSimbolo), PRATA[0], noAro);
        d[o + 1] = mix(mix(corCampo[1] * luz, sg, noSimbolo), PRATA[1], noAro);
        d[o + 2] = mix(mix(corCampo[2] * luz, sb, noSimbolo), PRATA[2], noAro);
        d[o + 3] = 255;
        var q = o + l * 4;
        d[q] = Math.round(Math.min(1, h + gui * 0.012 * (1 - metal)) * 255);
        d[q + 1] = Math.round(metal * 255);
        d[q + 2] = Math.round(aspero * 255);
        d[q + 3] = 255;
      }
    }
  }
  // Para as imagens paradas e a bancada: a face inteira, de uma vez.
  function face(id) {
    if (faces[id]) return faces[id];
    var j = { id: id, etapa: 0, linha: 0 };
    fila.unshift(j);
    while (!faces[id]) passo(j);
    return faces[id];
  }

  function smooth(a, b, x) { var t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); }
  function mix(a, b, t) { return a + (b - a) * t; }

  // MARK: Geometria

  var RAIO = 1, ESPESSURA = 0.17, CHANFRO = 0.05;

  function geometria(segs) {
    var pos = [], nor = [], uv = [], parte = [];
    var idx = { frente: [], verso: [], borda: [] };
    var ri = RAIO - CHANFRO, meia = ESPESSURA / 2;
    function v(x, y, z, nx, ny, nz, u, w, p) {
      pos.push(x, y, z); nor.push(nx, ny, nz); uv.push(u, w); parte.push(p);
      return pos.length / 3 - 1;
    }
    var i, a;
    var cf = v(0, 0, meia, 0, 0, 1, 0.5, 0.5, 0), cv = v(0, 0, -meia, 0, 0, -1, 0.5, 0.5, 1);
    var anelF = [], anelV = [];
    for (i = 0; i <= segs; i++) {
      a = (i / segs) * Math.PI * 2;
      var x = Math.cos(a) * ri, y = Math.sin(a) * ri;
      anelF.push(v(x, y, meia, 0, 0, 1, 0.5 + (x / ri) * RAIO_UV, 0.5 - (y / ri) * RAIO_UV, 0));
      anelV.push(v(x, y, -meia, 0, 0, -1, 0.5 - (x / ri) * RAIO_UV, 0.5 - (y / ri) * RAIO_UV, 1));
    }
    for (i = 0; i < segs; i++) {
      idx.frente.push(cf, anelF[i], anelF[i + 1]);
      idx.verso.push(cv, anelV[i + 1], anelV[i]);
    }
    // O perfil da borda: chanfro de cima, lado serrilhado, chanfro de baixo.
    var grupos = [[], [], []];
    var k, passos = 7, ang;
    for (k = 0; k <= passos; k++) {
      ang = Math.PI / 2 - (k / passos) * (Math.PI / 2);
      grupos[0].push([ri + CHANFRO * Math.cos(ang), meia - CHANFRO + CHANFRO * Math.sin(ang), Math.cos(ang), Math.sin(ang), 2]);
    }
    grupos[1].push([RAIO, meia - CHANFRO, 1, 0, 3], [RAIO, -(meia - CHANFRO), 1, 0, 3]);
    for (k = 0; k <= passos; k++) {
      ang = -(k / passos) * (Math.PI / 2);
      grupos[2].push([ri + CHANFRO * Math.cos(ang), -(meia - CHANFRO) + CHANFRO * Math.sin(ang), Math.cos(ang), Math.sin(ang), 2]);
    }
    grupos.forEach(function (perfil) {
      var aneis = perfil.map(function (p) {
        var anel = [];
        for (var j = 0; j <= segs; j++) {
          var b = (j / segs) * Math.PI * 2, cs = Math.cos(b), sn = Math.sin(b);
          anel.push(v(cs * p[0], sn * p[0], p[1], cs * p[2], sn * p[2], p[3], 0, 0, p[4]));
        }
        return anel;
      });
      for (var r = 0; r < aneis.length - 1; r++) {
        for (var j = 0; j < segs; j++) {
          var A = aneis[r][j], B = aneis[r + 1][j], C = aneis[r + 1][j + 1], D = aneis[r][j + 1];
          idx.borda.push(A, B, C, A, C, D);
        }
      }
    });
    return { pos: new Float32Array(pos), nor: new Float32Array(nor), uv: new Float32Array(uv), parte: new Float32Array(parte), idx: idx };
  }

  // MARK: Shaders

  function unit(v) { var n = Math.hypot(v[0], v[1], v[2]); return [v[0] / n, v[1] / n, v[2] / n]; }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function f(n) { return n.toFixed(5); }
  function v3(v) { return "vec3(" + f(v[0]) + "," + f(v[1]) + "," + f(v[2]) + ")"; }

  // O estudio: caixas de luz como direcoes, com largura e altura (na projecao) e forca.
  function caixasDeLuz(soFaixas) {
    var lista = [
      { c: [-0.55, 0.62, 0.62], tam: [0.95, 0.5], forca: 5.2 },   // a principal, alto a esquerda
      { c: [0.9, 0.05, 0.35], tam: [0.11, 1.5], forca: 3.4 },     // a faixa alta a direita
      { c: [0.05, 1.0, 0.08], tam: [1.4, 0.13], forca: 2.0 },     // a faixa do teto
      { c: [0.25, 0.35, -1.0], tam: [1.1, 0.5], forca: 2.6 },     // o contorno, de tras
      { c: [-0.95, -0.15, 0.2], tam: [0.08, 0.9], forca: 1.1 },   // um friso fino a esquerda
      { c: [-1.0, 0.25, 0.55], tam: [0.45, 0.8], forca: 1.2 },    // o rebatedor grande a esquerda
      { c: [0.12, 0.28, 1.0], tam: [0.62, 0.42], forca: 1.0 },    // o difusor grande, perto da camera
    ];
    if (soFaixas) lista = lista.filter(function (l) { return Math.min(l.tam[0], l.tam[1]) < 0.2; });
    return lista.map(function (l) {
      var c = unit(l.c);
      var cima = Math.abs(c[1]) > 0.9 ? [0, 0, 1] : [0, 1, 0];
      var t = unit(cross(cima, c)), b = cross(c, t);
      return "cor += vec3(" + f(l.forca) + ") * atenua * caixa(d, " + v3(c) + ", " + v3(t) + ", " + v3(b) + ", vec2(" + f(l.tam[0]) + "," + f(l.tam[1]) + "), suave);";
    }).join("\n  ");
  }

  var VERTICE = [
    "attribute vec3 aPos; attribute vec3 aNor; attribute vec2 aUv; attribute float aParte;",
    "uniform mat4 uModelo; uniform mat4 uVP;",
    "varying vec3 vPosW; varying vec3 vPosL; varying vec3 vNorL; varying vec2 vUv; varying float vParte;",
    "void main() {",
    "  vec4 w = uModelo * vec4(aPos, 1.0);",
    "  vPosW = w.xyz; vPosL = aPos; vNorL = aNor; vUv = aUv; vParte = aParte;",
    "  gl_Position = uVP * w;",
    "}",
  ].join("\n");

  function fragmento(derivadas) {
    return [
      derivadas ? "#extension GL_OES_standard_derivatives : enable" : "",
      "precision highp float;",
      "varying vec3 vPosW; varying vec3 vPosL; varying vec3 vNorL; varying vec2 vUv; varying float vParte;",
      "uniform sampler2D uTex; uniform mat3 uRot; uniform vec3 uCam; uniform vec3 uBorda;",
      "uniform float uModo; uniform float uAlfa; uniform float uExpo; uniform float uRelevo; uniform float uSerrilha;",
      "float caixa(vec3 d, vec3 c, vec3 t, vec3 b, vec2 tam, float suave) {",
      "  float k = dot(d, c);",
      "  if (k <= 0.0) return 0.0;",
      "  vec2 p = abs(vec2(dot(d, t), dot(d, b)) / k);",
      "  vec2 q = smoothstep(tam + suave, tam - suave * 0.6, p);",
      "  return q.x * q.y;",
      "}",
      "vec3 ambiente(vec3 d, float r) {",
      "  float suave = 0.03 + r * 0.7;",
      "  float atenua = 1.0 / (1.0 + r * r * 5.0);",
      "  float y = d.y;",
      "  vec3 cor = mix(vec3(0.006), vec3(0.05), smoothstep(-0.6, 0.15, y)) + vec3(0.09) * smoothstep(0.1, 1.0, y);",
      "  " + caixasDeLuz(),
      "  return cor;",
      "}",
      // O verniz do esmalte reflete so as faixas de luz, finas: as caixas grandes, somadas a
      // cor, apagavam o esmalte.
      "vec3 faixas(vec3 d) {",
      "  float suave = 0.03; float atenua = 1.0;",
      "  vec3 cor = vec3(0.0);",
      "  " + caixasDeLuz(true),
      "  return cor;",
      "}",
      "vec2 brdf(float nv, float r) {",
      "  vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);",
      "  vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);",
      "  vec4 q = r * c0 + c1;",
      "  float a = min(q.x * q.x, exp2(-9.28 * nv)) * q.x + q.y;",
      "  return vec2(-1.04, 1.04) * a + q.zw;",
      "}",
      "vec3 irradiancia(vec3 n) {",
      "  vec3 chave = " + v3(unit([-0.55, 0.62, 0.62])) + ";",
      "  return vec3(0.12 + 0.58 * max(dot(n, chave), 0.0) + 0.14 * max(n.y, 0.0) + 0.3 * max(n.z, 0.0));",
      "}",
      // O tom do Khronos PBR Neutral: a cor da marca no esmalte sai como a cor da marca, e so o brilho forte e comprimido.
      "vec3 neutro(vec3 c) {",
      "  float x = min(c.r, min(c.g, c.b));",
      "  float desvio = x < 0.08 ? x - 6.25 * x * x : 0.04;",
      "  c -= desvio;",
      "  float pico = max(c.r, max(c.g, c.b));",
      "  if (pico < 0.76) return c;",
      "  float d = 0.24;",
      "  float novo = 1.0 - d * d / (pico + d - 0.76);",
      "  c *= novo / pico;",
      "  float g = 1.0 - 1.0 / (0.15 * (pico - novo) + 1.0);",
      "  return mix(c, vec3(novo), g);",
      "}",
      "vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }",
      "float altura(vec2 uv) { return texture2D(uTex, vec2(0.5 + uv.x * 0.5, uv.y)).r; }",
      "void main() {",
      "  vec3 nl; vec3 base; float metal; float aspero; float verniz = 0.0; float ao = 1.0;",
      "  vec3 plano = normalize(uRot * vec3(0.0, 0.0, vNorL.z > 0.0 ? 1.0 : -1.0));",
      "  if (uModo < 0.5) {",
      "    vec4 cor = texture2D(uTex, vec2(vUv.x * 0.5, vUv.y));",
      "    vec3 rel = texture2D(uTex, vec2(0.5 + vUv.x * 0.5, vUv.y)).rgb;",
      "    float e = 1.0 / 512.0;",
      "    float hx = (altura(vUv + vec2(e, 0.0)) - altura(vUv - vec2(e, 0.0))) / (2.0 * e);",
      "    float hy = (altura(vUv + vec2(0.0, e)) - altura(vUv - vec2(0.0, e))) / (2.0 * e);",
      "    float escala = uRelevo * 0.49 / 0.95;",
      "    float frente = vNorL.z > 0.0 ? 1.0 : -1.0;",
      "    vec2 g = vec2(hx * frente, -hy) * escala;",
      "    nl = normalize(vec3(-g.x, -g.y, frente));",
      "    base = lin(cor.rgb); metal = rel.g; aspero = rel.b;",
      "    verniz = (1.0 - smoothstep(0.2, 0.5, metal)) * (1.0 - smoothstep(0.55, 0.65, aspero));",
      "    float hb = texture2D(uTex, vec2(0.5 + vUv.x * 0.5, vUv.y), 3.0).r;",
      "    ao = 1.0 - clamp((hb - rel.r) * 1.8, 0.0, 0.5);",
      "  } else {",
      "    nl = normalize(vNorL);",
      "    base = lin(uBorda); metal = 1.0; aspero = 0.15;",
      "    if (vParte > 2.5) {",
      "      float teta = atan(vPosL.y, vPosL.x) * uSerrilha;",
      "      float fade = 1.0;",
      derivadas ? "      fade = 1.0 - smoothstep(0.6, 1.6, fwidth(teta));" : "      fade = 0.5;",
      "      vec3 tang = vec3(-sin(atan(vPosL.y, vPosL.x)), cos(atan(vPosL.y, vPosL.x)), 0.0);",
      "      nl = normalize(nl + tang * sin(teta) * 0.75 * fade);",
      "      ao = mix(1.0, 0.72 + 0.28 * (0.5 + 0.5 * cos(teta)), fade);",
      "      aspero = 0.24;",
      "    }",
      "  }",
      "  vec3 n = normalize(uRot * nl);",
      "  vec3 vista = normalize(uCam - vPosW);",
      "  float nv = clamp(dot(n, vista), 0.001, 1.0);",
      "  vec3 refl = reflect(-vista, n);",
      "  vec3 f0 = mix(vec3(0.04), base, metal);",
      "  vec2 ab = brdf(nv, aspero);",
      "  vec3 brilho = ambiente(refl, aspero) * (f0 * ab.x + ab.y) * mix(0.18, 1.0, metal);",
      "  vec3 difusa = base * (1.0 - metal) * irradiancia(n);",
      "  vec3 cor = (difusa + brilho) * ao;",
      "  if (verniz > 0.0) {",
      "    float nvp = clamp(dot(plano, vista), 0.001, 1.0);",
      "    float fc = 0.04 + 0.96 * pow(1.0 - nvp, 5.0);",
      // O verniz so mostra o reflexo forte das caixas de luz: o brilho fraco, somado a cor, apagava o esmalte.
      "    vec3 camada = faixas(reflect(-vista, plano)) * fc;",
      "    cor = mix(cor, cor * (1.0 - fc) + camada, verniz);",
      "  }",
      "  cor = clamp(neutro(cor * uExpo), 0.0, 1.0);",
      "  gl_FragColor = vec4(pow(cor, vec3(1.0 / 2.2)) * uAlfa, uAlfa);",
      "}",
    ].join("\n");
  }

  // MARK: Matrizes (coluna por coluna, como o WebGL quer)

  function perspectiva(fov, aspecto, perto, longe) {
    var t = 1 / Math.tan(fov / 2), nf = 1 / (perto - longe);
    return [t / aspecto, 0, 0, 0, 0, t, 0, 0, 0, 0, (longe + perto) * nf, -1, 0, 0, 2 * longe * perto * nf, 0];
  }
  function multiplicar(a, b) {
    var o = new Array(16);
    for (var c = 0; c < 4; c++) for (var r = 0; r < 4; r++) {
      o[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3];
    }
    return o;
  }
  // Giro em Y, depois X, depois Z (o eixo da moeda), como em rotY * rotX * rotZ.
  function rotacao(rx, ry, rz) {
    var cx = Math.cos(rx), sx = Math.sin(rx), cy = Math.cos(ry), sy = Math.sin(ry), cz = Math.cos(rz), sz = Math.sin(rz);
    // Linhas da matriz R = Ry * Rx * Rz.
    var m00 = cy * cz + sy * sx * sz, m01 = -cy * sz + sy * sx * cz, m02 = sy * cx;
    var m10 = cx * sz, m11 = cx * cz, m12 = -sx;
    var m20 = -sy * cz + cy * sx * sz, m21 = sy * sz + cy * sx * cz, m22 = cy * cx;
    return [m00, m10, m20, m01, m11, m21, m02, m12, m22];
  }

  // MARK: O palco (um contexto WebGL num canvas)

  function Palco(canvas, opcoes) {
    opcoes = opcoes || {};
    this.canvas = canvas;
    this.fov = (opcoes.fov || 26) * Math.PI / 180;
    this.distancia = opcoes.distancia || 14;
    this.dprMax = opcoes.dprMax || 2;
    this.dpr = Math.min(window.devicePixelRatio || 1, this.dprMax);
    this.exposicao = opcoes.exposicao || 1.0;
    var gl = canvas.getContext("webgl", { alpha: true, antialias: true, premultipliedAlpha: true, depth: true, powerPreference: "high-performance", failIfMajorPerformanceCaveat: true });
    if (!gl) throw new Error("sem WebGL");
    this.gl = gl;
    var derivadas = !!gl.getExtension("OES_standard_derivatives");
    this.anisotropia = gl.getExtension("EXT_texture_filter_anisotropic") || gl.getExtension("WEBKIT_EXT_texture_filter_anisotropic");
    this.programa = this.compilar(VERTICE, fragmento(derivadas));
    var p = this.programa;
    this.u = {};
    ["uModelo", "uVP", "uTex", "uRot", "uCam", "uBorda", "uModo", "uAlfa", "uExpo", "uRelevo", "uSerrilha"].forEach(function (n) {
      this.u[n] = gl.getUniformLocation(p, n);
    }, this);
    var geo = geometria(opcoes.segmentos || 144);
    this.buffers = {};
    var self = this;
    [["aPos", geo.pos, 3], ["aNor", geo.nor, 3], ["aUv", geo.uv, 2], ["aParte", geo.parte, 1]].forEach(function (a) {
      var b = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, b);
      gl.bufferData(gl.ARRAY_BUFFER, a[1], gl.STATIC_DRAW);
      var loc = gl.getAttribLocation(p, a[0]);
      self.buffers[a[0]] = { b: b, loc: loc, n: a[2] };
    });
    var todos = geo.idx.frente.concat(geo.idx.verso, geo.idx.borda);
    this.faixas = {
      frente: [0, geo.idx.frente.length],
      verso: [geo.idx.frente.length, geo.idx.verso.length],
      borda: [geo.idx.frente.length + geo.idx.verso.length, geo.idx.borda.length],
    };
    this.indices = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.indices);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(todos), gl.STATIC_DRAW);
    this.texturas = {};
    this.prontas = {};
    // Na bancada e nas imagens paradas, a face sai na hora; na pagina, em fatias.
    this.esperar = !!opcoes.esperar;
    this.moedas = [];
    this.perdido = false;
    canvas.addEventListener("webglcontextlost", function (e) { e.preventDefault(); self.perdido = true; if (self.aoPerder) self.aoPerder(); });
    this.redimensionar();
  }

  Palco.prototype.compilar = function (vs, fs) {
    var gl = this.gl;
    function sh(tipo, fonte) {
      var s = gl.createShader(tipo);
      gl.shaderSource(s, fonte);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    }
    var p = gl.createProgram();
    gl.attachShader(p, sh(gl.VERTEX_SHADER, vs));
    gl.attachShader(p, sh(gl.FRAGMENT_SHADER, fs));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    return p;
  };

  Palco.prototype.textura = function (id, esperar) {
    if (this.texturas[id]) return this.texturas[id];
    if (!faces[id]) {
      if (esperar) face(id); else { pedirFace(id); return null; }
    }
    var gl = this.gl;
    var t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, face(id));
    gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    if (this.anisotropia) gl.texParameterf(gl.TEXTURE_2D, this.anisotropia.TEXTURE_MAX_ANISOTROPY_EXT, 4);
    this.texturas[id] = t;
    return t;
  };

  Palco.prototype.redimensionar = function () {
    var r = this.canvas.getBoundingClientRect();
    this.largura = Math.max(1, r.width);
    this.altura = Math.max(1, r.height);
    var w = Math.round(this.largura * this.dpr), h = Math.round(this.altura * this.dpr);
    if (this.canvas.width !== w || this.canvas.height !== h) { this.canvas.width = w; this.canvas.height = h; }
  };

  // Meia largura e meia altura do quadro visivel no plano z (mundo), com a camera em
  // (0, 0, distancia) olhando para a origem.
  Palco.prototype.meioQuadro = function (z) {
    var hh = Math.tan(this.fov / 2) * (this.distancia - (z || 0));
    return { w: hh * (this.largura / this.altura), h: hh };
  };

  // Um ponto da tela (px, a partir do canto do canvas) no plano z do mundo.
  Palco.prototype.daTela = function (x, y, z) {
    var m = this.meioQuadro(z);
    return [((x / this.largura) * 2 - 1) * m.w, (1 - (y / this.altura) * 2) * m.h];
  };

  Palco.prototype.desenhar = function (moedas) {
    if (this.perdido) return;
    var gl = this.gl;
    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    if (!moedas.length) return;
    gl.useProgram(this.programa);
    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.CULL_FACE);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    var self = this;
    Object.keys(this.buffers).forEach(function (k) {
      var b = self.buffers[k];
      if (b.loc < 0) return;
      gl.bindBuffer(gl.ARRAY_BUFFER, b.b);
      gl.enableVertexAttribArray(b.loc);
      gl.vertexAttribPointer(b.loc, b.n, gl.FLOAT, false, 0, 0);
    });
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.indices);
    var proj = perspectiva(this.fov, this.largura / this.altura, 0.5, 60);
    var vista = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, -this.distancia, 1];
    gl.uniformMatrix4fv(this.u.uVP, false, new Float32Array(multiplicar(proj, vista)));
    gl.uniform3f(this.u.uCam, 0, 0, this.distancia);
    gl.uniform1f(this.u.uExpo, this.exposicao);
    gl.uniform1f(this.u.uRelevo, 0.05);
    gl.uniform1f(this.u.uSerrilha, 150);
    gl.uniform1i(this.u.uTex, 0);
    gl.activeTexture(gl.TEXTURE0);
    // De tras para a frente, para o esmaecer sair certo.
    var ordem = moedas.filter(function (m) { return m.alfa > 0.003 && m.escala > 0.001; })
      .sort(function (a, b) { return a.z - b.z; });
    var agora = performance.now();
    ordem.forEach(function (m) {
      var frente = self.textura(m.id, self.esperar), verso = self.textura(m.verso || "verso", self.esperar);
      if (!frente || !verso) return;
      var chegou = self.prontas[m.id] || (self.prontas[m.id] = agora);
      var alfa = m.alfa * (self.esperar ? 1 : Math.min(1, (agora - chegou) / 450));
      var r = rotacao(m.rx || 0, m.ry || 0, m.rz || 0), s = m.escala;
      var modelo = [r[0] * s, r[1] * s, r[2] * s, 0, r[3] * s, r[4] * s, r[5] * s, 0, r[6] * s, r[7] * s, r[8] * s, 0, m.x, m.y, m.z, 1];
      gl.uniformMatrix4fv(self.u.uModelo, false, new Float32Array(modelo));
      gl.uniformMatrix3fv(self.u.uRot, false, new Float32Array(r));
      gl.uniform1f(self.u.uAlfa, alfa);
      var borda = m.borda || PRATA;
      gl.uniform3f(self.u.uBorda, borda[0] / 255, borda[1] / 255, borda[2] / 255);
      gl.uniform1f(self.u.uModo, 0);
      gl.bindTexture(gl.TEXTURE_2D, frente);
      gl.drawElements(gl.TRIANGLES, self.faixas.frente[1], gl.UNSIGNED_SHORT, self.faixas.frente[0] * 2);
      gl.bindTexture(gl.TEXTURE_2D, verso);
      gl.drawElements(gl.TRIANGLES, self.faixas.verso[1], gl.UNSIGNED_SHORT, self.faixas.verso[0] * 2);
      gl.uniform1f(self.u.uModo, 1);
      gl.drawElements(gl.TRIANGLES, self.faixas.borda[1], gl.UNSIGNED_SHORT, self.faixas.borda[0] * 2);
    });
  };

  Palco.prototype.destruir = function () {
    var ext = this.gl.getExtension("WEBGL_lose_context");
    if (ext) ext.loseContext();
  };

  // MARK: As cenas da pagina

  function lim(v, a, b) { return v < a ? a : v > b ? b : v; }
  function curva(a, b, x) { var t = lim((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }
  function saida(t) { return 1 - Math.pow(1 - t, 3); }
  function giroMaisPerto(angulo) { return Math.round(angulo / (Math.PI * 2)) * Math.PI * 2; }

  // A abertura. Cada moeda: id, posicao na tela (-1 a 1), profundidade e tamanho.
  var FORMACAO = {
    largo: [
      ["bitcoin", 0.72, -0.2, 2.2, 0.74],
      ["ethereum", -0.68, 0.34, 1.0, 0.68],
      ["tether", 0.82, 0.56, -1.6, 0.6],
      ["ripple", -0.44, 0.68, -3.4, 0.55],
      ["near", -0.86, -0.54, 0.4, 0.55],
      ["solana", -0.62, -0.08, -3.8, 0.58],
      ["avalanche-2", 0.4, 0.68, -5.0, 0.55],
      ["the-open-network", 0.92, -0.74, -1.8, 0.58],
      ["usd-coin", -0.96, 0.62, -6.0, 0.55],
      ["sui", 0.42, -0.88, -6.5, 0.5],
    ],
    estreito: [
      ["bitcoin", 0.86, -0.63, 1.0, 0.42],
      ["ethereum", -0.82, -0.5, 0.4, 0.38],
      ["tether", 0.92, 0.775, -2.5, 0.3],
      ["ripple", -0.9, 0.79, -3.0, 0.28],
      ["near", -0.78, -0.87, -1.5, 0.34],
      ["solana", 0.78, -0.92, -2.0, 0.36],
      ["sui", 0.97, -0.33, -3.5, 0.3],
    ],
  };
  // As moedas que pousam na lista de ativos da tela da Carteira (midia/carteira.webp): o
  // centro de cada logo, em fracao da tela do app, medido na gravacao.
  var POUSO = { tether: 0.5208, ripple: 0.5942, near: 0.6673, solana: 0.7407, sui: 0.8141 };
  var POUSO_X = 0.0986, POUSO_D = 0.0986;
  // Onde as outras ficam, em volta do iPhone, quando a pagina rola: lado e altura em
  // relacao a tela do app, profundidade e tamanho.
  var AUREOLA = {
    // Cada uma fica do lado de onde veio, para nao cruzar o iPhone; a esquerda, acima da legenda.
    bitcoin: [1.62, 0.32, 1.2, 0.74],
    ethereum: [-0.8, 0.04, -1.6, 0.52],
    "the-open-network": [1.9, 0.74, -2.6, 0.52],
    "usd-coin": [-1.75, -0.04, -6, 0.48],
    "avalanche-2": [1.45, 0.95, -5.5, 0.44],
  };

  function diretorAbertura(palco, t, estado) {
    var largo = palco.largura >= 900 || palco.largura / palco.altura > 1;
    var lista = largo ? FORMACAO.largo : FORMACAO.estreito;
    // No tablet em pe, a mesma formacao do celular, com moedas maiores.
    var maior = !largo && palco.largura >= 600 ? 1.4 : 1;
    var p = estado.p || 0;
    var tela = estado.tela;
    var px = estado.ponteiro || { x: 0, y: 0 };
    var moedas = [];
    var pousadas = 0;
    lista.forEach(function (f, i) {
      var id = f[0], fase = i * 1.7 + 0.4;
      var m = palco.meioQuadro(f[3]);
      var entrada = saida(lim((t - (estado.inicio || 0) - 0.12 * i) / 1.3, 0, 1));
      // Quase sempre de frente, balancando; de tempos em tempos, um giro inteiro. Rolando a
      // pagina, duas voltas, para chegar de frente no fim.
      var periodo = 8.5 + (i % 4) * 2.1;
      var dentro = (t + fase * 1.9) % periodo;
      var volta = dentro < 1.5 ? dentro / 1.5 : 1;
      volta = volta < 0.5 ? 4 * volta * volta * volta : 1 - Math.pow(-2 * volta + 2, 3) / 2;
      var giro = Math.sin(t * 0.45 + fase) * 0.42 * (1 - curva(0.5, 0.9, p) * 0.6) + volta * Math.PI * 2 + curva(0, 0.55, p) * Math.PI * 2 * (1 + (i % 2));
      var c = {
        id: id,
        x: f[1] * m.w + px.x * 0.35 * (f[3] + 7) / 9,
        y: f[2] * m.h + Math.sin(t * 0.8 + fase) * 0.09 - px.y * 0.25 * (f[3] + 7) / 9 - (1 - entrada) * 1.2,
        z: f[3],
        rx: -0.18 + Math.sin(t * 0.5 + fase) * 0.16 - px.y * 0.25,
        ry: giro + px.x * 0.45,
        rz: Math.sin(t * 0.3 + fase) * 0.12,
        escala: f[4] * maior * (0.6 + 0.4 * entrada),
        alfa: entrada,
      };
      if (tela && POUSO[id] !== undefined) {
        // Pousa no logo da lista: de frente, no plano z = 0, do tamanho do logo, e some.
        var ordem = Object.keys(POUSO).indexOf(id);
        var k = curva(0.24 + ordem * 0.045, 0.44 + ordem * 0.045, p);
        if (k > 0) {
          var alvo = palco.daTela(tela.left + tela.width * POUSO_X, tela.top + tela.height * POUSO[id], 0);
          var raio = (tela.width * POUSO_D / 2) * (2 * palco.meioQuadro(0).w / palco.largura);
          var e = k * k * (3 - 2 * k);
          var arco = Math.sin(e * Math.PI) * 0.9;
          c.x = c.x + (alvo[0] - c.x) * e;
          c.y = c.y + (alvo[1] - c.y) * e + arco * 0.4;
          c.z = c.z + (0 - c.z) * e + arco * 1.2;
          c.escala = c.escala + (raio - c.escala) * e;
          var frente = giroMaisPerto(c.ry);
          c.ry = c.ry + (frente - c.ry) * e;
          c.rx = c.rx * (1 - e);
          c.rz = c.rz * (1 - e);
          c.alfa = entrada * (1 - curva(0.86, 1, k));
          if (k >= 1) pousadas++;
        }
      } else if (tela && AUREOLA[id] && !largo) {
        // No celular nao ha lado livre: as outras saem pela borda e somem.
        var s = curva(0.2, 0.55, p);
        c.x += (f[1] > 0 ? 1 : -1) * s * palco.meioQuadro(f[3]).w * 0.9;
        c.alfa = entrada * (1 - s);
      } else if (tela && AUREOLA[id]) {
        var a = AUREOLA[id];
        var q = curva(0.28, 0.6, p);
        if (q > 0) {
          var z = a[2];
          var pos = palco.daTela(tela.left + tela.width * a[0], tela.top + tela.height * a[1], z);
          var w = q * q * (3 - 2 * q);
          c.x = c.x + (pos[0] + Math.sin(t * 0.6 + fase) * 0.15 - c.x) * w;
          c.y = c.y + (pos[1] + Math.cos(t * 0.5 + fase) * 0.12 - c.y) * w;
          c.z = c.z + (z - c.z) * w;
          c.escala = c.escala + (a[3] - c.escala) * w;
        }
      }
      // A imersao no iPhone: as que ficaram de fora passam voando pela camera e somem.
      var imersao = curva(0.8, 0.95, p);
      if (imersao > 0) {
        var fora = c.alfa > 0.01 && !(tela && POUSO[id] !== undefined);
        c.escala *= 1 + imersao * (fora ? 2.2 : 0);
        c.z += imersao * 6;
        c.x *= 1 + imersao * 1.6;
        c.y *= 1 + imersao * 1.6;
        c.alfa *= 1 - curva(0.82, 0.93, p);
      }
      moedas.push(c);
    });
    return moedas;
  }

  function Cena(canvas, opcoes, diretor) {
    this.canvas = canvas;
    this.diretor = diretor;
    this.palco = new Palco(canvas, opcoes);
    this.visivel = false;
    this.parada = false;
    this.ultimo = 0;
    var self = this;
    new IntersectionObserver(function (entradas) {
      self.visivel = entradas[0].isIntersecting;
      if (self.visivel && window.EscaliburRelogio) window.EscaliburRelogio.pedir();
    }, { rootMargin: "120px" }).observe(canvas);
  }

  var ponteiro = { x: 0, y: 0, alvoX: 0, alvoY: 0 };
  window.addEventListener("pointermove", function (e) {
    if (e.pointerType && e.pointerType !== "mouse") return;
    ponteiro.alvoX = (e.clientX / window.innerWidth) * 2 - 1;
    ponteiro.alvoY = (e.clientY / window.innerHeight) * 2 - 1;
  }, { passive: true });

  function iniciar() {
    var relogio = window.EscaliburRelogio;
    if (!relogio || !window.IntersectionObserver) return;
    var raiz = document.documentElement;
    var cenas = [];
    var desistiu = false;
    var lento = { soma: 0, n: 0 };
    var inicio = performance.now() / 1000;
    var moedaEscolhida = window.EscaliburPrecos ? window.EscaliburPrecos.atual() : "bitcoin";
    var giro = { de: moedaEscolhida, para: moedaEscolhida, desde: -10 };

    function desistir() {
      if (desistiu) return;
      desistiu = true;
      raiz.classList.remove("com-3d");
      cenas.forEach(function (c) { c.parada = true; try { c.palco.destruir(); } catch (e) { /* ja perdido */ } });
    }

    try {
      var c1 = document.querySelector(".abertura-3d");
      if (c1) {
        var cenaAbertura = new Cena(c1, { dprMax: 2, exposicao: 1.05 }, function (palco, t) {
          var ab = window.EscaliburAbertura || { p: 0 };
          var tela = null;
          if (ab.tela) {
            var r = ab.tela(), rc = palco.canvas.getBoundingClientRect();
            tela = { left: r.left - rc.left, top: r.top - rc.top, width: r.width, height: r.height };
          }
          return diretorAbertura(palco, t, { p: ab.p, tela: tela, ponteiro: ponteiro, inicio: inicio });
        });
        cenaAbertura.pesada = true;
        cenas.push(cenaAbertura);
      }
      // A cabeca da pagina Redes: as mesmas moedas da abertura, paradas no lugar, girando.
      var c4 = document.querySelector(".redes-3d");
      if (c4) {
        // Nas bordas, longe do texto: seis moedas no largo, quatro nos cantos no celular.
        var BORDAS = [
          ["bitcoin", -0.78, 0.34, 0.9, 1], ["ethereum", 0.8, 0.4, 0.2, 1], ["solana", -0.86, -0.36, -1.2, 1],
          ["tether", 0.84, -0.34, -0.6, 1], ["ripple", -0.5, -0.62, -3, 0], ["the-open-network", 0.54, 0.66, -3, 0],
        ];
        cenas.push(new Cena(c4, { dprMax: 2, exposicao: 1.05 }, function (palco, t) {
          var estreito = palco.largura < 700;
          var lado = Math.min(palco.meioQuadro(0).w, palco.meioQuadro(0).h);
          return BORDAS.filter(function (b) { return !estreito || b[4]; }).map(function (b, i) {
            var m = palco.meioQuadro(b[3]);
            var x = b[1] * m.w, y = b[2] * m.h;
            if (estreito) { x = (b[1] > 0 ? 1.02 : -1.02) * m.w; y = (b[2] > 0 ? 0.9 : -0.86) * m.h; }
            var entrada = saida(lim((t - inicio - 0.15 * i) / 1.2, 0, 1));
            return {
              id: b[0], x: x + ponteiro.x * 0.25, y: y + Math.sin(t * 0.8 + i) * 0.08 - (1 - entrada) * 0.8, z: b[3],
              rx: -0.2 + Math.sin(t * 0.5 + i) * 0.15, ry: Math.sin(t * 0.45 + i * 1.7) * 0.5 + t * 0.25 * (i % 2 ? 1 : -1),
              rz: 0, escala: lado * (estreito ? 0.3 : 0.26), alfa: entrada,
            };
          });
        }));
      }
      var c2 = document.querySelector(".destaque-3d");
      if (c2) {
        cenas.push(new Cena(c2, { dprMax: 2, exposicao: 1.05, distancia: 12 }, function (palco, t) {
          var m = palco.meioQuadro(0);
          var raio = Math.min(m.w, m.h) / 1.4 * 0.96;
          var k = lim((t - giro.desde) / 0.9, 0, 1);
          var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
          if (k >= 0.5 && giro.de !== giro.para) giro.de = giro.para;
          var rc = palco.canvas.getBoundingClientRect();
          var dx = lim(((ponteiro.x + 1) / 2 * window.innerWidth - (rc.left + rc.width / 2)) / rc.width, -1, 1);
          var dy = lim(((ponteiro.y + 1) / 2 * window.innerHeight - (rc.top + rc.height / 2)) / rc.height, -1, 1);
          return [{
            id: giro.de, x: 0, y: Math.sin(t * 0.9) * 0.04, z: 0,
            rx: -0.16 + Math.sin(t * 0.45) * 0.06 + dy * 0.3,
            ry: Math.sin(t * 0.6) * 0.32 + e * Math.PI * 2 + dx * 0.5,
            rz: 0, escala: raio, alfa: 1,
          }];
        }));
      }
      var c3 = document.querySelector(".final-3d");
      if (c3) {
        var vistoEm = null;
        cenas.push(new Cena(c3, { dprMax: 2, exposicao: 1.05, distancia: 12 }, function (palco, t) {
          if (vistoEm === null) vistoEm = t;
          var m = palco.meioQuadro(0);
          var raio = Math.min(m.w, m.h) / 1.4 * 0.96;
          var chegada = saida(lim((t - vistoEm) / 2.2, 0, 1));
          var rc = palco.canvas.getBoundingClientRect();
          var dx = lim(((ponteiro.x + 1) / 2 * window.innerWidth - (rc.left + rc.width / 2)) / rc.width, -1, 1);
          // De frente quase sempre, balancando; a cada 7 s, uma volta inteira, mostrando o verso.
          var dentro = (t - vistoEm) % 7;
          var volta = dentro > 5.4 ? (dentro - 5.4) / 1.6 : 0;
          volta = volta < 0.5 ? 4 * volta * volta * volta : 1 - Math.pow(-2 * volta + 2, 3) / 2;
          return [{
            id: "escalibur", x: 0, y: Math.sin(t * 0.8) * 0.05, z: 0,
            rx: -0.14 + Math.sin(t * 0.4) * 0.07,
            ry: (1 - chegada) * Math.PI * 4 + Math.sin(t * 0.55) * 0.38 + volta * Math.PI * 2 + dx * 0.4,
            rz: 0, escala: raio, alfa: 1,
          }];
        }));
      }
    } catch (erro) {
      cenas.forEach(function (c) { try { c.palco.destruir(); } catch (e) { /* nada */ } });
      return;
    }
    if (!cenas.length) return;
    // As faces na ordem em que aparecem: o verso (todas usam), as da abertura, a do mercado e a do fim.
    ["verso"].concat((window.innerWidth >= 900 ? FORMACAO.largo : FORMACAO.estreito).map(function (f) { return f[0]; }),
      [moedaEscolhida, "escalibur"]).forEach(pedirFace);

    cenas.forEach(function (c) { c.palco.aoPerder = desistir; });
    document.addEventListener("escalibur:moeda", function (e) {
      giro.para = e.detail.id;
      giro.desde = performance.now() / 1000;
    });
    document.addEventListener("escalibur:calmo", desistir);
    relogio.aoMedir(function () { cenas.forEach(function (c) { c.palco.redimensionar(); }); });

    var primeiro = true;
    relogio.registrar(function (estado) {
      if (desistiu) return false;
      var t = estado.t;
      ponteiro.x += (ponteiro.alvoX - ponteiro.x) * 0.06;
      ponteiro.y += (ponteiro.alvoY - ponteiro.y) * 0.06;
      var algum = false;
      cenas.forEach(function (c) {
        if (c.parada || !c.visivel || document.hidden) return;
        algum = true;
        c.palco.desenhar(c.diretor(c.palco, t));
      });
      if (algum && primeiro) { primeiro = false; raiz.classList.add("com-3d"); }
      // O governador: se o quadro passa do tempo, a resolucao cai; se nem assim, as moedas
      // param e a imagem parada volta.
      if (algum) {
        if (cenas[0].ultimoT && !trabalhando) {
          var passo = (t - cenas[0].ultimoT) * 1000;
          if (passo > 0 && passo < 250) { lento.soma += passo; lento.n++; }
        }
        cenas[0].ultimoT = t;
        if (lento.n >= 90) {
          var media = lento.soma / lento.n;
          lento.soma = 0; lento.n = 0;
          if (media > 26) {
            var abaixou = false;
            cenas.forEach(function (c) {
              if (c.palco.dpr > 1.01) { c.palco.dpr = Math.max(1, c.palco.dpr - 0.5); c.palco.redimensionar(); abaixou = true; }
            });
            if (!abaixou && media > 36) desistir();
          }
        }
      } else {
        cenas[0].ultimoT = 0;
      }
      return algum;
    });
  }

  window.EscaliburMoedas = { Palco: Palco, face: face, MOEDAS: MOEDAS, diretorAbertura: diretorAbertura };
  if (!window.EscaliburMoedasSoMotor) iniciar();
})();
