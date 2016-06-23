package controller;
import db.UserContract;
import sugoi.form.elements.DateDropdowns;
import sugoi.form.elements.Input;
import sugoi.form.elements.Selectbox;
import sugoi.form.Form;
import db.Contract;
import Common;
import plugin.Tutorial;
using Std;

class Contract extends Controller
{

	public function new() 
	{
		super();
	}
	
	@tpl("contract/view.mtt")
	public function doView(c:db.Contract) {
		view.category = 'amap';
		view.c = c;
	}
	
	/**
	 * contrats de l'utilisateur en cours
	 */
	@tpl("contract/default.mtt")
	function doDefault() {
		
		var constOrders = null;
		var varOrders = new Map<String,Array<db.UserContract>>();
		
		var a = App.current.user.amap;		
		var oneMonthAgo = DateTools.delta(Date.now(), -1000.0 * 60 * 60 * 24 * 30);
		
		//commandes fixes
		var contracts = db.Contract.manager.search($type == db.Contract.TYPE_CONSTORDERS && $amap == a && $endDate > oneMonthAgo, false);		
		constOrders = [];
		for ( c in contracts){
			var orders = app.user.getOrdersFromContracts([c]);
			if (orders.length == 0) continue;
			constOrders.push({contract:c, orders:db.UserContract.prepare(orders) });
		}
		
		
		
		//commandes variables groupées par date de distrib
		var contracts = db.Contract.manager.search($type == db.Contract.TYPE_VARORDER && $amap == a && $endDate > oneMonthAgo, false);
		
		for (c in contracts) {
			var ds = c.getDistribs(false);
			for (d in ds) {
				//store orders in a stringmap like "2015-01-01" => [order1,order2,...]
				var k = d.date.toString().substr(0, 10);
				var orders = app.user.getOrdersFromDistrib(d);
				if (orders.length > 0) {
					if (!varOrders.exists(k)) {
						varOrders.set(k, Lambda.array(orders));
					}else {
						var z = varOrders.get(k).concat(Lambda.array(orders));
						varOrders.set(k, z);
					}	
				}
			}
		}
		
		//struct finale
		var varOrders2 = new Array<{date:Date,orders:Array<UserOrder>}>();
		for ( k in varOrders.keys()) {

			var d = new Date(k.split("-")[0].parseInt(), k.split("-")[1].parseInt() - 1, k.split("-")[2].parseInt(), 0, 0, 0);
			
			var orders = db.UserContract.prepare( Lambda.list(varOrders[k]) );
			
			varOrders2.push({date:d,orders:orders});
			

		}
		
		//trier la map par ordre chrono desc
		varOrders2.sort(function(b, a) {
			return Math.round(a.date.getTime()/1000)-Math.round(b.date.getTime()/1000);
		});
		
		view.varOrders = varOrders2;
		view.constOrders = constOrders;
		
		
		// tutorials
		if (app.user.isAmapManager()) {
			
			app.user.lock();
						
			//actions
			if (app.params.exists('startTuto') ) {
				
				//start a tuto
				var t = app.params.get('startTuto'); 
				
				app.user.tutoState = {name:t,step:0};
				app.user.update();
				
				
			}else if (app.params.exists('stopTuto')) {
				
				//stopped tuto from a tuto window
				app.user.tutoState = null;
				app.user.update();	
				
				view.stopTuto = true;
			}
			
		
			//tuto state
			var tutos = new Array<{name:String,completion:Float,key:String}>();
			
			for ( k in Tutorial.all().keys() ) {	
				var t = Tutorial.all().get(k);
				
				var completion = null;
				if (app.user.tutoState!=null && app.user.tutoState.name == k) completion = app.user.tutoState.step / t.steps.length;
				
				tutos.push( { name:t.name, completion:completion , key:k } );
			}
			
			view.tutos = tutos;
			
		}
		
	}
	

	/**
	 * Modifie un contrat
	 */
	@tpl("form.mtt")
	function doEdit(c:db.Contract) {
		
		if (!app.user.isContractManager(c)) throw Error('/', 'Action interdite');
		
		var currentContact = c.contact;
		var form = Form.fromSpod(c);
		form.removeElement( form.getElement("amapId") );
		form.removeElement(form.getElement("type"));
		form.getElement("userId").required = true;
		
		if (form.checkToken()) {
			form.toSpod(c);
			c.amap = app.user.amap;
			
			//checks & warnings
			if (c.hasPercentageOnOrders() && c.percentageValue==null) throw Error("/contract/edit/"+c.id, "Si vous souhaitez ajouter des frais au pourcentage de la commande, spécifiez le pourcentage et son libellé.");
			
			if (c.hasStockManagement()) {
				for (p in c.getProducts()) {
					if (p.stock == null) {
						app.session.addMessage("Attention, vous avez activé la gestion des stocks. Pensez à renseigner le champs \"stock\" de tout vos produits", true);
						break;
					}
				}
			}
			
			//no stock mgmt for constant orders
			if (c.hasStockManagement() && c.type==db.Contract.TYPE_CONSTORDERS) {
				c.flags.unset(ContractFlags.StockManagement);
				app.session.addMessage("La gestion des stocks n'est pas disponible pour les contrats de type AMAP", true);
			}
			
			
			c.update();
			
			//update rights
			if ( c.contact != null && (currentContact==null || c.contact.id!=currentContact.id) ) {
				var ua = db.UserAmap.get(c.contact, app.user.amap, true);
				ua.giveRight(ContractAdmin(c.id));
				ua.giveRight(Messages);
				ua.giveRight(Membership);
				ua.update();
				
				//remove rights to old contact
				if (currentContact != null) {
					var x = db.UserAmap.get(currentContact, c.amap, true);
					if (x != null) {
						x.removeRight(ContractAdmin(c.id));
						x.update();						
					}
				}
				
			}
			
			throw Ok("/contractAdmin/view/"+c.id, "Contrat mis à jour");
		}
		
		view.form = form;
	}
	
	@tpl("contract/insertChoose.mtt")
	function doInsertChoose() {
		//checkToken();
		
	}
	
	/**
	 * Créé un nouveau contrat
	 */
	@tpl("form.mtt")
	function doInsert(?type:Int) {
		if (!app.user.isAmapManager()) throw Error('/', 'Action interdite');
		if (type == null) throw Redirect('/contract/insertChoose');
		
		view.title = if (type == db.Contract.TYPE_CONSTORDERS)"Créer un contrat à commande fixe"else"Créer un contrat à commande variable";
		
		var c = new db.Contract();
		
		var form = Form.fromSpod(c);
		form.removeElement( form.getElement("amapId") );
		form.removeElement(form.getElement("type"));
		form.getElement("userId").required = true;
			
		if (form.checkToken()) {
			form.toSpod(c);
			c.amap = app.user.amap;
			c.type = type;
			c.insert();
			
			//right
			if (c.contact != null) {
				var ua = db.UserAmap.get(c.contact, app.user.amap, true);
				ua.giveRight(ContractAdmin(c.id));
				ua.giveRight(Messages);
				ua.giveRight(Membership);
				ua.update();
			}
			
			throw Ok("/contractAdmin/view/"+c.id, "Nouveau contrat créé");
		}
		
		view.form = form;
	}
	
	function doDelete(c:db.Contract/*,args:{chk:String}*/) {
		
		if (!app.user.isAmapManager()) throw Error("/contractAdmin", "Vous n'avez pas le droit de supprimer un contrat");
		
		if (checkToken()) {
			
			//verif qu'il n'y a pas de commandes sur ce contrat
			var products = c.getProducts();
			var orders = db.UserContract.manager.count($productId in Lambda.map(products, function(p) return p.id));
			if (orders > 0) {
				throw Error("/contractAdmin", "Vous ne pouvez pas effacer ce contrat car il y a des commandes rattachées à ce contrat.");
			}
			
			//remove admin rights and delete contract		
			var ua = db.UserAmap.get(c.contact, c.amap, true);
			if (ua != null) {
				ua.removeRight(ContractAdmin(c.id));
				ua.update();	
			}	
			c.lock();
			c.delete();
			throw Ok("/contractAdmin", "Contrat supprimé");
			
		}
		
		throw Error("/contractAdmin","Erreur de token");
	}
	
	/**
	 * Make an order by contract.
	 * The form is prepopulated if orders have already been made
	 */
	@tpl("contract/order.mtt")
	function doOrder(c:db.Contract ) {
		
		//checks
		if (app.user.amap.hasShopMode()) throw Redirect("/shop");
		if (!c.isUserOrderAvailable()) throw Error("/", "Ce contrat n'est pas ouvert aux commandes ");
		/*if (c.type == db.Contract.TYPE_VARORDER && args.d == null ) {
			throw Error("/", "Ce contrat est à commande variable, vous devez sélectionner une date de distribution pour faire votre commande.");
		}*/
		
		var distributions = [];
		/* If its a varying contract, we display a column by distribution*/
		if (c.type == db.Contract.TYPE_VARORDER) {
			distributions = db.Distribution.getOpenToOrdersDeliveries(c);
			
			//if ( !args.d.canOrder() ) throw Error("/contract", "Les commandes sont fermées pour cette distribution, impossible de modifier la commande.");
			
		}else {
			
			distributions = [null]; 
			//view.distributions = c.getDistribs(false);
		}
		
		//list of distribs with a list of product and optionnaly an order
		var userOrders = new Array< {distrib:db.Distribution,datas:Array<{order:db.UserContract,product:db.Product}>} >();
		var products = c.getProducts();
		for ( d in distributions){
			var datas = [];
			for ( p in products) {
				var ua = { order:null, product:p };
				
				var order : db.UserContract = null;
				if (c.type == db.Contract.TYPE_VARORDER) {
					order = db.UserContract.manager.select($user == app.user && $productId == p.id && $distributionId==d.id, true);	
				}else {
					order = db.UserContract.manager.select($user == app.user && $productId == p.id, true);
				}
				
				if (order != null) ua.order = order;
				datas.push(ua);
			}
			
			userOrders.push({distrib:d,datas:datas});
		}
		
		
		//form check
		if (checkToken()) {
			
			//get dsitrib if needed
			var distrib : db.Distribution = null;
			if (c.type == db.Contract.TYPE_VARORDER) {
				distrib = db.Distribution.manager.get(Std.parseInt(app.params.get("distribution")), false);
			}
			
			for (k in app.params.keys()) {
				
				if (k.substr(0, 1) != "d") continue;
				var qt = app.params.get(k);
				if (qt == "") continue;
				
				var pid = null;
				var did = null;
				try{
				pid = Std.parseInt(k.split("-")[1].substr(1));
				did = Std.parseInt(k.split("-")[0].substr(1));
				}catch (e:Dynamic){trace("unable to parse key "+k); }
				
				//find related element in userOrders
				var uo = null;
				for ( x in userOrders){
					if (x.distrib!=null && x.distrib.id != did) {
						continue;
					}else{
						for (a in x.datas){
							if (a.product.id == pid){
								uo = a;
								break;
							}
						}
					}
				}
				
				if (uo == null) throw "Impossible de retrouver le produit " + pid +" et distribution "+did;
					
				var q = 0.0;
				
				if (uo.product.hasFloatQt ) {
					var param = StringTools.replace(qt, ",", ".");
					q = Std.parseFloat(param);
				}else {
					q = Std.parseInt(qt);
				}
				
				
				if (uo.order != null) {	
					//trace("updating order q="+q);
					db.UserContract.edit(uo.order, q);
					
				}else {
					//trace("new order q="+q);
					db.UserContract.make(app.user, q, uo.product.id, did);
				}
				
			}
			//if (distrib != null) {
				//throw Ok("/contract/order/" + c.id+"?d="+distrib.id, "Votre commande a été mise à jour");	
			//}else {
				throw Ok("/contract/order/"+c.id, "Votre commande a été mise à jour");
				//trace("ok");
			//}
			
		}
		
		view.c = view.contract = c;
		view.userOrders = userOrders;
		
	}
	
	/**
	 * Modifier une commande en fonction du jour de distribution (tout fournisseurs confondus)
	 */
	@tpl("contract/orderByDate.mtt")
	function doEditOrderByDate(date:Date) {
		
		// cannot edit order if date is in the past
		if (Date.now().getTime() > date.getTime()) {
			
			var msg = "Cette distribution a déjà eu lieu, vous ne pouvez plus modifier la commande.";
			if (app.user.isContractManager()) msg += "<br/>En tant que gestionnaire de contrat vous pouvez modifier une commande depuis la page de gestion des commandes dans <a href='/contractAdmin'>Gestion contrats</a> ";
			
			throw Error("/contract", msg);
		}
		
		// Il faut regarder le contrat de chaque produit et verifier si le contrat est toujours ouvert à la commande.		
		var d1 = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0);
		var d2 = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59);

		var cids = Lambda.map(app.user.amap.getActiveContracts(true), function(c) return c.id);
		var distribs = db.Distribution.manager.search(($contractId in cids) && $date >= d1 && $date <=d2 , false);
		var orders = db.UserContract.manager.search($userId==app.user.id && $distributionId in Lambda.map(distribs,function(d)return d.id)  );
		view.orders = db.UserContract.prepare(orders);
		view.date = date;
		
		//form check
		if (checkToken()) {
			
			for (k in app.params.keys()) {
				var param = app.params.get(k);
				if (k.substr(0, "product".length) == "product") {
					
					//trouve le produit dans userOrders
					var pid = Std.parseInt(k.substr("product".length));
					var order = Lambda.find(orders, function(uo) return uo.product.id == pid);
					if (order == null) throw "Erreur, impossible de retrouver la commande";
					
					var q = 0.0;
					if (order.product.hasFloatQt ) {
						param = StringTools.replace(param, ",", ".");
						q = Std.parseFloat(param);
					}else {
						q = Std.parseInt(param);
					}
					
					var quantity = Math.abs( q==null?0:q );

					if ( order.distribution.canOrderNow() ) {
						//met a jour la commande
						db.UserContract.edit(order, quantity);
					}
					
				}
			}
			
			throw Ok("/contract", "Votre commande a été mise à jour");	
			
		}
	}
}